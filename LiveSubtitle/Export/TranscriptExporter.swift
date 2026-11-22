import Foundation

/// 导出格式。都是纯文本，任何 App 都能打开：
/// - TXT：纯文字，适合粘贴进笔记、文档、聊天
/// - SRT / VTT：带时间轴的字幕文件，可直接导入剪映、Premiere、Final Cut、YouTube
/// - Markdown：带时间戳的会议记录，适合 Notion、Obsidian、备忘录
enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case txt, srt, vtt, markdown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .txt: "纯文本"
        case .srt: "SRT 字幕"
        case .vtt: "WebVTT 字幕"
        case .markdown: "Markdown 笔记"
        }
    }

    var subtitle: String {
        switch self {
        case .txt: "粘贴到备忘录、微信、文档"
        case .srt: "剪映、Premiere、Final Cut 通用"
        case .vtt: "网页播放器、YouTube"
        case .markdown: "带时间戳，适合 Notion / Obsidian"
        }
    }

    var symbol: String {
        switch self {
        case .txt: "doc.plaintext"
        case .srt: "captions.bubble"
        case .vtt: "play.rectangle"
        case .markdown: "text.badge.checkmark"
        }
    }

    var fileExtension: String {
        switch self {
        case .txt: "txt"
        case .srt: "srt"
        case .vtt: "vtt"
        case .markdown: "md"
        }
    }
}

enum TranscriptExporter {
    static func render(_ transcript: Transcript, as format: ExportFormat) -> String {
        switch format {
        case .txt: plainText(transcript)
        case .srt: srt(transcript)
        case .vtt: vtt(transcript)
        case .markdown: markdown(transcript)
        }
    }

    /// 写入临时目录，返回可以交给分享面板的文件 URL。
    static func writeFile(_ transcript: Transcript, as format: ExportFormat) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(baseFileName(for: transcript)).\(format.fileExtension)")
        try render(transcript, as: format).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func baseFileName(for transcript: Transcript) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return "字幕 \(formatter.string(from: transcript.startedAt))"
    }

    // MARK: 各格式

    static func plainText(_ t: Transcript) -> String {
        // 每段一行，便于在其他 App 里继续编辑
        t.segments.map(\.text).joined(separator: "\n") + "\n"
    }

    static func srt(_ t: Transcript) -> String {
        cues(t).enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.start, separator: ",")) --> \(timestamp(cue.end, separator: ","))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    static func vtt(_ t: Transcript) -> String {
        "WEBVTT\n\n" + cues(t).map { cue in
            "\(timestamp(cue.start, separator: ".")) --> \(timestamp(cue.end, separator: "."))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    static func markdown(_ t: Transcript) -> String {
        let date = t.startedAt.formatted(date: .long, time: .shortened)
        var lines = [
            "# 实时字幕记录",
            "",
            "- 时间：\(date)",
            "- 语言：\(Locale.current.localizedString(forIdentifier: t.localeIdentifier) ?? t.localeIdentifier)",
            "- 时长：\(clock(t.duration))",
            "",
            "---",
            "",
        ]
        for segment in t.segments {
            lines.append("**[\(clock(segment.start))]** \(segment.text)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: 工具

    /// 字幕文件里每条至少显示 1 秒，且不和下一条重叠。
    private static func cues(_ t: Transcript) -> [TranscriptSegment] {
        var result = t.segments
        for i in result.indices {
            var end = max(result[i].end, result[i].start + 1)
            if i + 1 < result.count { end = min(end, max(result[i + 1].start, result[i].start + 0.3)) }
            result[i].end = end
        }
        return result
    }

    /// 00:01:02,345
    static func timestamp(_ seconds: TimeInterval, separator: String) -> String {
        let totalMillis = Int((max(seconds, 0) * 1000).rounded())
        let h = totalMillis / 3_600_000
        let m = totalMillis / 60_000 % 60
        let s = totalMillis / 1000 % 60
        let ms = totalMillis % 1000
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, separator, ms)
    }

    /// 1:02 或 1:02:03
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
