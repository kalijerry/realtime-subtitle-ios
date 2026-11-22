import SwiftData
import SwiftUI

/// 全屏黑底字幕主界面。
/// 轻点屏幕可以隐藏 / 显示控件，只留下字幕本身。
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @State private var transcriber = LiveTranscriber()
    @State private var chromeVisible = true
    @State private var showSettings = false
    @State private var showExport = false
    @State private var showHistory = false
    @State private var savedToast = false
    /// 当前这次录音对应的记录；每确定一句就更新一次
    @State private var currentRecording: Recording?

    @AppStorage(DisplaySettings.fontSizeKey) private var fontSize = DisplaySettings.defaultFontSize
    @AppStorage(DisplaySettings.alignmentKey) private var alignment = SubtitleAlignment.leading
    @AppStorage(DisplaySettings.fadeHistoryKey) private var fadeHistory = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if transcriber.hasContent {
                SubtitleStage(
                    segments: transcriber.segments,
                    volatileText: transcriber.volatileText,
                    fontSize: fontSize,
                    alignment: alignment,
                    fadeHistory: fadeHistory,
                    topInset: chromeVisible ? 96 : 40,
                    bottomInset: chromeVisible ? 190 : 60
                )
                .transition(.opacity)
            } else {
                EmptyStateView(isListening: transcriber.isListening, locale: transcriber.locale)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            VStack(spacing: 0) {
                if chromeVisible {
                    TopBar(
                        transcriber: transcriber,
                        onSettings: { showSettings = true }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                if savedToast {
                    Label("已保存到历史记录", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if chromeVisible {
                    BottomBar(
                        transcriber: transcriber,
                        onHistory: { showHistory = true },
                        onExport: { showExport = true }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            StatusOverlay(transcriber: transcriber)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.smooth(duration: 0.3)) { chromeVisible.toggle() }
        }
        .animation(.smooth(duration: 0.4), value: transcriber.hasContent)
        .preferredColorScheme(.dark)
        .statusBarHidden(!chromeVisible)
        .persistentSystemOverlays(chromeVisible ? .automatic : .hidden)
        .sensoryFeedback(trigger: transcriber.isListening) { _, listening in
            listening ? .start : .stop
        }
        .onChange(of: transcriber.isListening) { _, listening in
            // 录音时保持屏幕常亮；停止后若控件被隐藏，自动唤回，方便分享
            UIApplication.shared.isIdleTimerDisabled = listening
            if listening {
                currentRecording = nil
            } else {
                withAnimation(.smooth) { chromeVisible = true }
            }
        }
        .onChange(of: transcriber.phase) { old, new in
            if old == .finishing, new == .idle, currentRecording != nil {
                flashSavedToast()
            }
        }
        .onChange(of: transcriber.segments) { _, segments in
            saveProgress(segments)
        }
        .task { await transcriber.loadLocales() }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(transcriber: transcriber)
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(transcript: transcriber.transcript)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
        }
    }

    /// 每确定一句就写入数据库：一次录音对应一条记录。
    private func saveProgress(_ segments: [TranscriptSegment]) {
        guard !segments.isEmpty else { return }
        let transcript = transcriber.transcript
        let recording: Recording
        if let currentRecording {
            recording = currentRecording
        } else {
            recording = Recording(createdAt: transcript.startedAt, localeIdentifier: transcript.localeIdentifier)
            context.insert(recording)
            currentRecording = recording
        }
        recording.update(with: transcript)
        try? context.save()
    }

    private func flashSavedToast() {
        withAnimation(.smooth) { savedToast = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.smooth) { savedToast = false }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Recording.self, inMemory: true)
}
