import AVFoundation

/// 麦克风采集：AVAudioEngine 抓取 PCM，转换成 SpeechAnalyzer 需要的格式后交给回调。
///
/// 这个类刻意不放在 MainActor 上：音频 tap 回调运行在实时音频线程里。
final class AudioCapture: @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case noInputAvailable

        var errorDescription: String? {
            switch self {
            case .noInputAvailable: "没有可用的麦克风输入"
            }
        }
    }

    private let engine = AVAudioEngine()
    private let converter = BufferConverter()

    func start(
        targetFormat: AVAudioFormat,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw CaptureError.noInputAvailable
        }

        let converter = self.converter
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            onLevel(Self.level(of: buffer))
            if let converted = try? converter.convert(buffer, to: targetFormat) {
                onBuffer(converted)
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 0...1 的响度，用于界面上的声波指示。
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        let rms = (sum / Float(count)).squareRoot()
        let db = 20 * log10(max(rms, 0.000_01))
        // -55 dB 视为静音，-10 dB 视为满格
        return min(max((db + 55) / 45, 0), 1)
    }
}

/// 把麦克风原生格式（通常 48kHz Float32）转换成分析器需要的格式（通常 16kHz Int16）。
final class BufferConverter: @unchecked Sendable {
    enum ConversionError: Error {
        case failedToCreateConverter
        case failedToCreateBuffer
        case conversionFailed(NSError?)
    }

    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else { return buffer }

        if converter == nil || converter?.inputFormat != inputFormat || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            // 不做 priming，避免每个 buffer 前端被吃掉几帧
            converter?.primeMethod = .none
        }
        guard let converter else { throw ConversionError.failedToCreateConverter }

        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            throw ConversionError.failedToCreateBuffer
        }

        var nsError: NSError?
        var consumed = false
        let status = converter.convert(to: output, error: &nsError) { _, inputStatus in
            defer { consumed = true }
            inputStatus.pointee = consumed ? .noDataNow : .haveData
            return consumed ? nil : buffer
        }
        guard status != .error else { throw ConversionError.conversionFailed(nsError) }
        return output
    }
}
