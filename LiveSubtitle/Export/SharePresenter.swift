import UIKit

/// 直接弹出系统分享面板（UIActivityViewController）。
/// 比 SwiftUI 的 ShareLink 更可靠：在 sheet 里、列表里、iPad 上都能正常弹出。
@MainActor
enum SharePresenter {
    static func share(_ items: [Any]) {
        guard let top = topViewController() else { return }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            // iPad 必须给锚点，否则会崩溃
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 80, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }

    static func share(_ transcript: Transcript, as format: ExportFormat) {
        do {
            let url = try TranscriptExporter.writeFile(transcript, as: format)
            share([url])
        } catch {
            // 写文件失败时退而求其次，直接分享文字
            share([TranscriptExporter.render(transcript, as: format)])
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
