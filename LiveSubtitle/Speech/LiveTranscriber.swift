import AVFoundation
import Foundation
import Observation
import Speech

/// 核心管线：麦克风 → SpeechAnalyzer(SpeechTranscriber) → 临时结果 + 确定结果。
///
/// - 临时结果（volatile）：识别过程中不断被覆盖，显示为半透明的“正在说”的一行。
/// - 确定结果（finalized）：不再变化，追加进 `segments`，形成滚动字幕。
@MainActor
@Observable
final class LiveTranscriber {
    enum Phase: Equatable {
        case idle
        case preparing
        case downloadingModel(progress: Double)
        case listening
        case finishing
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .preparing, .downloadingModel, .finishing: true
            default: false
            }
        }
    }

    // MARK: 对界面公开的状态

    private(set) var phase: Phase = .idle
    private(set) var segments: [TranscriptSegment] = []
    private(set) var volatileText: String = ""
    private(set) var audioLevel: Float = 0
    private(set) var startedAt: Date?
    private(set) var availableLocales: [Locale] = []
    var locale: Locale

    var isListening: Bool { phase == .listening }
    var hasContent: Bool { !segments.isEmpty || !volatileText.isEmpty }

    var transcript: Transcript {
        Transcript(
            segments: segments,
            localeIdentifier: locale.identifier,
            startedAt: startedAt ?? .now
        )
    }

    // MARK: 内部

    private let capture = AudioCapture()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    init() {
        let saved = UserDefaults.standard.string(forKey: "transcriberLocale")
        locale = saved.map(Locale.init(identifier:)) ?? Locale.current
    }

    // MARK: 语言

    func loadLocales() async {
        let supported = await SpeechTranscriber.supportedLocales
        let preferred = ["zh-CN", "zh-TW", "zh-HK", "en-US", "en-GB", "ja-JP", "ko-KR", "fr-FR", "de-DE", "es-ES"]
        availableLocales = supported.sorted { lhs, rhs in
            let l = preferred.firstIndex(of: lhs.identifier(.bcp47)) ?? Int.max
            let r = preferred.firstIndex(of: rhs.identifier(.bcp47)) ?? Int.max
            if l != r { return l < r }
            return Self.displayName(for: lhs) < Self.displayName(for: rhs)
        }
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            locale = match
        }
    }

    func select(_ newLocale: Locale) {
        guard !isListening else { return }
        locale = newLocale
        UserDefaults.standard.set(newLocale.identifier, forKey: "transcriberLocale")
    }

    static func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    // MARK: 开始 / 停止

    func toggle() async {
        if isListening { await stop() } else { await start() }
    }

    func start() async {
        guard !phase.isBusy, !isListening else { return }

        guard await AVAudioApplication.requestRecordPermission() else {
            phase = .failed("需要麦克风权限。请到「设置 › 实时字幕」中打开麦克风。")
            return
        }

        phase = .preparing
        do {
            guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
                throw TranscriberError.unsupportedLocale(Self.displayName(for: locale))
            }

            let transcriber = SpeechTranscriber(
                locale: supported,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: [.audioTimeRange]
            )

            try await ensureModelInstalled(for: transcriber)

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw TranscriberError.noAudioFormat
            }

            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            self.analyzer = analyzer
            self.inputContinuation = continuation

            // 新的一次录音：清空上一次的内容
            segments = []
            volatileText = ""

            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        self?.handle(result)
                    }
                } catch {
                    self?.fail(error)
                }
            }

            try await analyzer.start(inputSequence: stream)

            try capture.start(
                targetFormat: format,
                onBuffer: { buffer in
                    continuation.yield(AnalyzerInput(buffer: buffer))
                },
                onLevel: { [weak self] level in
                    Task { @MainActor in self?.updateLevel(level) }
                }
            )

            startedAt = .now
            phase = .listening
        } catch {
            await tearDown()
            fail(error)
        }
    }

    func stop() async {
        guard isListening else { return }
        phase = .finishing
        capture.stop()
        inputContinuation?.finish()
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            await analyzer?.cancelAndFinishNow()
        }
        await resultsTask?.value
        commitVolatileText()
        await tearDown()
        phase = .idle
    }

    func clear() {
        guard !isListening else { return }
        segments = []
        volatileText = ""
        startedAt = nil
        if case .failed = phase { phase = .idle }
    }

    func dismissError() {
        if case .failed = phase { phase = .idle }
    }

    // MARK: 结果处理

    private func handle(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
        if result.isFinal {
            volatileText = ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let start = result.range.start.seconds
            let end = result.range.end.seconds
            let lastEnd = segments.last?.end ?? 0
            segments.append(TranscriptSegment(
                text: trimmed,
                start: start.isFinite ? start : lastEnd,
                end: end.isFinite ? end : lastEnd
            ))
        } else {
            volatileText = text
        }
    }

    /// 停止时如果还有没确定的临时文字，也保留下来，避免丢字。
    private func commitVolatileText() {
        let trimmed = volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        volatileText = ""
        guard !trimmed.isEmpty else { return }
        let lastEnd = segments.last?.end ?? 0
        let elapsed = startedAt.map { Date.now.timeIntervalSince($0) } ?? lastEnd
        segments.append(TranscriptSegment(text: trimmed, start: lastEnd, end: max(lastEnd, elapsed)))
    }

    private func updateLevel(_ level: Float) {
        // 平滑一下，让声波动画不抖
        audioLevel = isListening ? audioLevel * 0.5 + level * 0.5 : 0
    }

    private func fail(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        phase = .failed(message)
    }

    private func tearDown() async {
        capture.stop()
        inputContinuation?.finish()
        inputContinuation = nil
        resultsTask = nil
        analyzer = nil
        audioLevel = 0
    }

    // MARK: 模型下载

    /// 本机模型由系统管理；第一次使用某种语言时需要下载，之后完全离线。
    private func ensureModelInstalled(for transcriber: SpeechTranscriber) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return // 已安装
        }
        phase = .downloadingModel(progress: 0)
        let progress = request.progress
        let watcher = Task { [weak self] in
            while !Task.isCancelled {
                self?.phase = .downloadingModel(progress: progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { watcher.cancel() }
        try await request.downloadAndInstall()
        phase = .preparing
    }
}

enum TranscriberError: LocalizedError {
    case unsupportedLocale(String)
    case noAudioFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let name): "本机转写暂不支持「\(name)」，请换一种语言。"
        case .noAudioFormat: "无法获取语音模型需要的音频格式。"
        }
    }
}
