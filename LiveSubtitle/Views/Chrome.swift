import SwiftUI

// MARK: - 顶栏

struct TopBar: View {
    let transcriber: LiveTranscriber
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if transcriber.isListening, let startedAt = transcriber.startedAt {
                LiveBadge(startedAt: startedAt, level: transcriber.audioLevel)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            } else {
                Text("实时字幕")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.opacity)
            }

            Spacer(minLength: 8)

            LanguageMenu(transcriber: transcriber)

            Button(action: onSettings) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("显示设置")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .animation(.smooth(duration: 0.3), value: transcriber.isListening)
    }
}

/// 录音中：红点 + 计时 + 声波。
struct LiveBadge: View {
    let startedAt: Date
    let level: Float

    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 9, height: 9)
                .shadow(color: .red.opacity(0.8), radius: pulsing ? 6 : 2)
                .opacity(pulsing ? 1 : 0.55)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
                .onAppear { pulsing = true }

            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                Text(TranscriptExporter.clock(context.date.timeIntervalSince(startedAt)))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            LevelMeter(level: level)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在录音")
    }
}

/// 五根随音量起伏的小竖条。
struct LevelMeter: View {
    let level: Float

    private let weights: [CGFloat] = [0.55, 0.85, 1, 0.75, 0.5]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(weights.indices, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 3, height: 4 + 14 * CGFloat(level) * weights[i])
            }
        }
        .frame(height: 18)
        .animation(.smooth(duration: 0.12), value: level)
    }
}

struct LanguageMenu: View {
    let transcriber: LiveTranscriber

    var body: some View {
        Menu {
            Picker("识别语言", selection: Binding(
                get: { transcriber.locale.identifier },
                set: { id in
                    if let locale = transcriber.availableLocales.first(where: { $0.identifier == id }) {
                        transcriber.select(locale)
                    }
                }
            )) {
                ForEach(transcriber.availableLocales, id: \.identifier) { locale in
                    Text(LiveTranscriber.displayName(for: locale)).tag(locale.identifier)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text(shortName)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 44)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(transcriber.isListening || transcriber.phase.isBusy)
        .opacity(transcriber.isListening ? 0.6 : 1)
        .accessibilityLabel("识别语言：\(LiveTranscriber.displayName(for: transcriber.locale))")
    }

    private var shortName: String {
        let locale = transcriber.locale
        let language = Locale.current.localizedString(forLanguageCode: locale.language.languageCode?.identifier ?? "")
        return language ?? locale.identifier
    }
}

// MARK: - 底栏

struct BottomBar: View {
    let transcriber: LiveTranscriber
    let onHistory: () -> Void
    let onExport: () -> Void

    private var canShare: Bool {
        !transcriber.phase.isBusy && !transcriber.segments.isEmpty
    }

    var body: some View {
        GlassEffectContainer(spacing: 24) {
            HStack(spacing: 36) {
                CircleIconButton(symbol: "clock.arrow.circlepath", label: "历史记录", action: onHistory)
                    .disabled(transcriber.phase.isBusy)

                RecordButton(
                    isListening: transcriber.isListening,
                    isBusy: transcriber.phase.isBusy,
                    level: transcriber.audioLevel
                ) {
                    Task { await transcriber.toggle() }
                }

                CircleIconButton(symbol: "square.and.arrow.up", label: "分享", action: onExport)
                    .disabled(!canShare)
                    .opacity(canShare ? 1 : 0.35)
            }
        }
        .padding(.bottom, 20)
    }
}

struct CircleIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

/// 类似相机快门的录音键：空闲时红色圆点，录音时变成圆角方块，外圈随音量呼吸。
struct RecordButton: View {
    let isListening: Bool
    let isBusy: Bool
    let level: Float
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // 音量光晕
                Circle()
                    .fill(.red.opacity(0.28))
                    .frame(width: 84, height: 84)
                    .scaleEffect(isListening ? 1 + CGFloat(level) * 0.35 : 1)
                    .opacity(isListening ? 1 : 0)
                    .blur(radius: 6)
                    .animation(.smooth(duration: 0.15), value: level)

                Circle()
                    .strokeBorder(.white.opacity(0.92), lineWidth: 4)
                    .frame(width: 84, height: 84)

                if isBusy {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                } else {
                    RoundedRectangle(cornerRadius: isListening ? 9 : 33, style: .continuous)
                        .fill(.red)
                        .frame(width: isListening ? 32 : 66, height: isListening ? 32 : 66)
                }
            }
            .frame(width: 96, height: 96)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(isBusy)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isListening)
        .accessibilityLabel(isListening ? "停止" : "开始实时字幕")
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let isListening: Bool
    let locale: Locale

    @State private var breathe = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(isListening ? 0.18 : 0.10), .clear],
                            center: .center, startRadius: 4, endRadius: 90
                        )
                    )
                    .frame(width: 180, height: 180)
                    .scaleEffect(breathe ? 1.08 : 0.92)

                Image(systemName: isListening ? "waveform" : "captions.bubble.fill")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, isActive: isListening)
                    .contentTransition(.symbolEffect(.replace))
            }

            VStack(spacing: 10) {
                Text(isListening ? "正在聆听…" : "把声音变成大字幕")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)

                Text(isListening
                     ? "开始说话，字幕会实时出现在这里"
                     : "轻点下方红色按钮开始\n全程在 iPhone 本机识别，不上传任何音频")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(32)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
        }
        .animation(.smooth(duration: 0.3), value: isListening)
    }
}

// MARK: - 状态浮层（准备 / 下载模型 / 出错）

struct StatusOverlay: View {
    let transcriber: LiveTranscriber

    var body: some View {
        Group {
            switch transcriber.phase {
            case .preparing:
                card {
                    ProgressView().tint(.white)
                    Text("正在准备语音模型…")
                }
            case .downloadingModel(let progress):
                card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("首次使用，正在下载\(LiveTranscriber.displayName(for: transcriber.locale))语音模型")
                        ProgressView(value: progress)
                            .tint(.white)
                        Text("\(Int(progress * 100))% · 下载后可离线使用")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            case .finishing:
                card {
                    ProgressView().tint(.white)
                    Text("正在整理最后一句…")
                }
            case .failed(let message):
                card {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("出了点问题", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.yellow)
                        Text(message)
                        Button("好") { transcriber.dismissError() }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
            case .idle, .listening:
                EmptyView()
            }
        }
        .animation(.smooth(duration: 0.3), value: transcriber.phase)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 14) { content() }
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: 360)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
            .padding(24)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
