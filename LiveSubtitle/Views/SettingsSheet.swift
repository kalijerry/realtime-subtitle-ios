import SwiftUI

struct SettingsSheet: View {
    let transcriber: LiveTranscriber

    @Environment(\.dismiss) private var dismiss
    @AppStorage(DisplaySettings.fontSizeKey) private var fontSize = DisplaySettings.defaultFontSize
    @AppStorage(DisplaySettings.alignmentKey) private var alignment = SubtitleAlignment.leading
    @AppStorage(DisplaySettings.fadeHistoryKey) private var fadeHistory = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .listRowInsets(EdgeInsets())
                }

                Section("字幕") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("字号")
                            Spacer()
                            Text("\(Int(fontSize))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            Image(systemName: "textformat.size.smaller")
                            Slider(value: $fontSize, in: DisplaySettings.fontSizeRange, step: 2)
                            Image(systemName: "textformat.size.larger")
                        }
                        .foregroundStyle(.secondary)
                    }

                    Picker("对齐", selection: $alignment) {
                        ForEach(SubtitleAlignment.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Toggle("较早的字幕逐渐变暗", isOn: $fadeHistory)
                }

                Section {
                    Picker("识别语言", selection: localeBinding) {
                        ForEach(transcriber.availableLocales, id: \.identifier) { locale in
                            Text(LiveTranscriber.displayName(for: locale)).tag(locale.identifier)
                        }
                    }
                    .disabled(transcriber.isListening)
                } header: {
                    Text("语言")
                } footer: {
                    Text("首次使用某种语言时，系统会下载对应的语音模型，之后可离线使用。")
                }

                Section {
                    Label("使用 iOS 26 SpeechAnalyzer，全程在本机识别", systemImage: "lock.shield")
                    Label("音频不会上传到任何服务器", systemImage: "icloud.slash")
                } footer: {
                    Text("录音时屏幕保持常亮；手动锁屏后也会在后台继续转写。双击字幕区域进入专注模式（只留字幕），轻点恢复。")
                }
            }
            .navigationTitle("显示设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var preview: some View {
        VStack(alignment: alignment.horizontal, spacing: fontSize * 0.3) {
            Text("这是较早的一句字幕")
                .foregroundStyle(.white.opacity(fadeHistory ? 0.5 : 1))
            Text("这是刚刚确定的一句")
                .foregroundStyle(.white)
            Text("正在说的话…")
                .foregroundStyle(.white.opacity(0.5))
        }
        .font(.system(size: fontSize * 0.6, weight: .bold))
        .multilineTextAlignment(alignment.text)
        .frame(maxWidth: .infinity, alignment: alignment.frame)
        .padding(24)
        .background(.black)
        .animation(.smooth(duration: 0.2), value: fontSize)
        .animation(.smooth(duration: 0.2), value: alignment)
    }

    private var localeBinding: Binding<String> {
        Binding(
            get: { transcriber.locale.identifier },
            set: { id in
                if let locale = transcriber.availableLocales.first(where: { $0.identifier == id }) {
                    transcriber.select(locale)
                }
            }
        )
    }
}
