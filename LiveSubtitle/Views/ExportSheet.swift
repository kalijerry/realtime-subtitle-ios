import SwiftUI

/// 导出面板：选择格式 → 系统分享面板，可以存到「文件」、AirDrop，或直接发到微信、备忘录、剪映等 App。
struct ExportSheet: View {
    let transcript: Transcript

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    stats
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                Section("分享为文件") {
                    ForEach(ExportFormat.allCases) { format in
                        row(for: format)
                    }
                }

                Section {
                    Button {
                        UIPasteboard.general.string = TranscriptExporter.plainText(transcript)
                        withAnimation(.smooth) { copied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.6))
                            withAnimation(.smooth) { copied = false }
                        }
                    } label: {
                        Label(copied ? "已拷贝" : "拷贝全部文字",
                              systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .sensoryFeedback(.success, trigger: copied) { _, new in new }
                }

                Section("预览") {
                    Text(TranscriptExporter.plainText(transcript))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("导出字幕")
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

    private var stats: some View {
        HStack(spacing: 0) {
            stat(value: "\(transcript.characterCount)", label: "字数")
            Divider().frame(height: 32)
            stat(value: TranscriptExporter.clock(transcript.duration), label: "时长")
            Divider().frame(height: 32)
            stat(value: "\(transcript.segments.count)", label: "句")
        }
        .padding(.vertical, 8)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(for format: ExportFormat) -> some View {
        let content = HStack(spacing: 14) {
            Image(systemName: format.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.tint, in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(format.title).foregroundStyle(.primary)
                    Text(".\(format.fileExtension)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(format.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(.tint)
        }

        return Button {
            SharePresenter.share(transcript, as: format)
        } label: {
            content.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
