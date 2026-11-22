import SwiftData
import SwiftUI

/// 历史记录：每次录音一条，按时间倒序，可搜索、查看、分享、重命名、删除。
struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @State private var search = ""

    private var filtered: [Recording] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return recordings }
        return recordings.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.fullText.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    ContentUnavailableView(
                        "还没有记录",
                        systemImage: "captions.bubble",
                        description: Text("每次录音结束都会自动保存在这里")
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    List {
                        ForEach(groupedByDay, id: \.day) { group in
                            Section(group.title) {
                                ForEach(group.items) { recording in
                                    NavigationLink(value: recording) {
                                        RecordingRow(recording: recording)
                                    }
                                }
                                .onDelete { offsets in
                                    for index in offsets { context.delete(group.items[index]) }
                                    try? context.save()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("历史记录")
            .navigationDestination(for: Recording.self) { RecordingDetailView(recording: $0) }
            .searchable(text: $search, prompt: "搜索文字")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private struct DayGroup {
        var day: Date
        var title: String
        var items: [Recording]
    }

    private var groupedByDay: [DayGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { day in
            let title: String
            if calendar.isDateInToday(day) {
                title = "今天"
            } else if calendar.isDateInYesterday(day) {
                title = "昨天"
            } else {
                title = day.formatted(.dateTime.year().month().day().weekday())
            }
            return DayGroup(day: day, title: title, items: groups[day] ?? [])
        }
    }
}

struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recording.displayTitle)
                .font(.headline)
                .lineLimit(1)
            Text(recording.fullText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 12) {
                Label(recording.createdAt.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                Label(TranscriptExporter.clock(recording.duration), systemImage: "waveform")
                Label("\(recording.characterCount) 字", systemImage: "character.textbox")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 4)
    }
}

/// 记录详情：黑底大字回看，带时间戳，可分享 / 拷贝 / 重命名 / 删除。
struct RecordingDetailView: View {
    @Bindable var recording: Recording

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(DisplaySettings.fontSizeKey) private var fontSize = DisplaySettings.defaultFontSize
    @State private var showExport = false
    @State private var renaming = false
    @State private var draftTitle = ""
    @State private var confirmDelete = false

    var body: some View {
        let segments = recording.segments
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recording.createdAt.formatted(date: .long, time: .shortened))
                    Text("\(TranscriptExporter.clock(recording.duration)) · \(recording.characterCount) 字 · \(LiveTranscriber.displayName(for: Locale(identifier: recording.localeIdentifier)))")
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.bottom, 6)

                ForEach(segments) { segment in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(TranscriptExporter.clock(segment.start))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white.opacity(0.4))
                        Text(segment.text)
                            .font(.system(size: max(20, fontSize * 0.6), weight: .semibold))
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(24)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(recording.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showExport = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享")

                Menu {
                    Button {
                        UIPasteboard.general.string = TranscriptExporter.plainText(recording.transcript)
                    } label: {
                        Label("拷贝全部文字", systemImage: "doc.on.doc")
                    }
                    Button {
                        draftTitle = recording.title
                        renaming = true
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(transcript: recording.transcript)
        }
        .alert("重命名", isPresented: $renaming) {
            TextField(recording.displayTitle, text: $draftTitle)
            Button("取消", role: .cancel) {}
            Button("保存") {
                recording.title = draftTitle
                try? context.save()
            }
        }
        .confirmationDialog("删除这条记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                context.delete(recording)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("删除后无法恢复。")
        }
    }
}
