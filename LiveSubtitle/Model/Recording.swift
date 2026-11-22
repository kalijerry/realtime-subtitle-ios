import Foundation
import SwiftData

/// 一次录音 = 一条记录。录音过程中每确定一句就写一次，App 被杀掉也不会丢。
@Model
final class Recording {
    var id: UUID = UUID()
    /// 用户自定义标题；为空时显示第一句话
    var title: String = ""
    var createdAt: Date = Date.now
    var localeIdentifier: String = ""
    var duration: TimeInterval = 0
    var characterCount: Int = 0
    /// 全文，用于列表预览和搜索
    var fullText: String = ""
    /// [TranscriptSegment] 的 JSON
    var segmentsData: Data = Data()

    init(createdAt: Date, localeIdentifier: String) {
        self.createdAt = createdAt
        self.localeIdentifier = localeIdentifier
    }

    var segments: [TranscriptSegment] {
        (try? JSONDecoder().decode([TranscriptSegment].self, from: segmentsData)) ?? []
    }

    func update(with transcript: Transcript) {
        segmentsData = (try? JSONEncoder().encode(transcript.segments)) ?? Data()
        duration = transcript.duration
        characterCount = transcript.characterCount
        fullText = transcript.segments.map(\.text).joined(separator: transcript.joinsWithoutSpaces ? "" : " ")
    }

    var transcript: Transcript {
        Transcript(segments: segments, localeIdentifier: localeIdentifier, startedAt: createdAt)
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = segments.first?.text ?? ""
        return firstLine.isEmpty ? "未命名记录" : String(firstLine.prefix(30))
    }
}
