import Foundation

/// 一段已确定（finalized）的字幕。时间以录音开始为 0 点，单位秒。
struct TranscriptSegment: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}

/// 一次完整的录音转写，用于导出。
struct Transcript: Sendable {
    var segments: [TranscriptSegment]
    var localeIdentifier: String
    var startedAt: Date

    var isEmpty: Bool { segments.isEmpty }

    var duration: TimeInterval { segments.last?.end ?? 0 }

    /// 中日韩文字不按空格计词，这里统计“字数”：去掉空白后的字符数。
    var characterCount: Int {
        segments.reduce(0) { $0 + $1.text.filter { !$0.isWhitespace }.count }
    }

    /// 中文、日文的句子之间不需要空格，其余语言用空格拼接。
    var joinsWithoutSpaces: Bool {
        let language = Locale(identifier: localeIdentifier).language.languageCode?.identifier ?? ""
        return ["zh", "ja", "yue"].contains(language)
    }
}
