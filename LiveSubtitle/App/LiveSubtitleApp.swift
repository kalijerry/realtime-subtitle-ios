import SwiftUI

@main
struct LiveSubtitleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// 用户可调的显示偏好，用 @AppStorage 持久化。
enum DisplaySettings {
    static let fontSizeKey = "subtitleFontSize"
    static let alignmentKey = "subtitleAlignment"
    static let fadeHistoryKey = "subtitleFadeHistory"

    static let defaultFontSize: Double = 40
    static let fontSizeRange: ClosedRange<Double> = 24...80
}

enum SubtitleAlignment: String, CaseIterable, Identifiable {
    case leading, center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leading: "左对齐"
        case .center: "居中"
        }
    }

    var horizontal: HorizontalAlignment { self == .leading ? .leading : .center }
    var frame: Alignment { self == .leading ? .leading : .center }
    var text: TextAlignment { self == .leading ? .leading : .center }
}
