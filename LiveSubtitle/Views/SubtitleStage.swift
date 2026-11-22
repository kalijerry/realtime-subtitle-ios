import SwiftUI

/// 字幕滚动区域。
/// - 确定结果：白色，越早的行越暗（可在设置中关闭）。
/// - 临时结果：半透明白色，紧跟在最后，随识别不断刷新。
/// - 自动滚到底；用户手动往上翻时暂停跟随，并出现「回到最新」。
struct SubtitleStage: View {
    let segments: [TranscriptSegment]
    let volatileText: String
    let fontSize: Double
    let alignment: SubtitleAlignment
    let fadeHistory: Bool
    let topInset: CGFloat
    let bottomInset: CGFloat

    @State private var position = ScrollPosition(edge: .bottom)
    @State private var followsLatest = true

    var body: some View {
        ScrollView {
            VStack(alignment: alignment.horizontal, spacing: fontSize * 0.42) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    line(segment.text)
                        .foregroundStyle(.white.opacity(opacity(forLineAt: index)))
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 12)),
                            removal: .opacity
                        ))
                }

                if !volatileText.isEmpty {
                    line(volatileText)
                        .foregroundStyle(.white.opacity(0.5))
                        .contentTransition(.opacity)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment.frame)
            .padding(.horizontal, 28)
            .animation(.smooth(duration: 0.35), value: segments.count)
        }
        .contentMargins(.top, topInset, for: .scrollContent)
        .contentMargins(.bottom, bottomInset, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.visibleRect.maxY >= geometry.contentSize.height - 80
        } action: { _, nearBottom in
            followsLatest = nearBottom
        }
        .onChange(of: segments.count) { scrollToLatest() }
        .onChange(of: volatileText) { scrollToLatest() }
        .onChange(of: fontSize) { scrollToLatest(force: true) }
        .mask {
            // 顶部渐隐：旧字幕像“滚出画面”一样慢慢消失
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.22),
                    .init(color: .black, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) {
            if !followsLatest {
                Button {
                    scrollToLatest(force: true)
                } label: {
                    Label("回到最新", systemImage: "arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.bottom, bottomInset - 56)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.smooth(duration: 0.25), value: followsLatest)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .lineSpacing(fontSize * 0.12)
            .multilineTextAlignment(alignment.text)
            .frame(maxWidth: .infinity, alignment: alignment.frame)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func opacity(forLineAt index: Int) -> Double {
        guard fadeHistory else { return 1 }
        // 有临时结果时，最后一条确定结果也算“上一行”
        let distance = segments.count - 1 - index + (volatileText.isEmpty ? 0 : 1)
        switch distance {
        case 0: return 1
        case 1: return 0.78
        case 2: return 0.58
        default: return 0.42
        }
    }

    private func scrollToLatest(force: Bool = false) {
        guard force || followsLatest else { return }
        withAnimation(.smooth(duration: 0.3)) {
            position.scrollTo(edge: .bottom)
        }
    }
}
