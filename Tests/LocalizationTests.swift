import AppKit

/// Exercises native bundle language negotiation and production permission views without
/// displaying windows, changing permissions, starting the controller or touching gamma.
@main
@MainActor
enum LocalizationTests {
    static func main() {
        let expected = CommandLine.arguments[1]
        let chinese = expected == "zh-Hans"
        precondition(Bundle.main.preferredLocalizations.first == expected,
                     "Unexpected language: \(Bundle.main.preferredLocalizations)")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let pending = PermissionWindow(trusted: false)
        let allowed = PermissionWindow(trusted: true)
        let drag = PermissionDragPanel()
        let pendingText = strings(in: pending.contentView!)
        precondition(pendingText.contains(chinese ? "设置 Curtain" : "Set Up Curtain"))
        precondition(pendingText.contains(chinese ? "允许" : "Allow"))
        let allowedText = strings(in: allowed.contentView!)
        precondition(allowedText.contains(chinese ? "设置完成" : "You're All Set"))
        precondition(allowedText.contains(chinese ? "已允许" : "Allowed"))
        let pendingHeight = pending.contentView!.bounds.height
        allowed.setTrusted(false)
        precondition(abs(allowed.contentView!.bounds.height - pendingHeight) < 1,
                     "Revoking permission must make room for the longer explanation")
        pending.setTrusted(true)
        precondition(strings(in: pending.contentView!).contains(chinese ? "设置完成" : "You're All Set"))

        let version = "0.2.3"
        precondition(String(localized: "Curtain \(version) Is Available") ==
                     (chinese ? "发现 Curtain 0.2.3" : "Curtain 0.2.3 Is Available"))
        precondition(UpdateFailure.noRelease.errorDescription ==
                     (chinese ? "尚无可用发布，请检查发布页面或稍后再试。" :
                                "No release is available yet. Check the release page or try again later."))

        // Check both actual guide layouts with native text measurement.
        for compact in [false, true] {
            drag.setCompact(compact)
            let hint = fields(in: drag.contentView!).first { $0.stringValue.hasPrefix(chinese ? "将 Curtain" : "Drag Curtain") }!
            let required = (hint.stringValue as NSString).boundingRect(
                with: NSSize(width: hint.bounds.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: hint.font!])
            precondition(ceil(required.height) <= hint.bounds.height, "Drag hint is clipped")
            for button in buttons(in: drag.contentView!) {
                precondition(drag.contentView!.bounds.contains(button.convert(button.bounds, to: drag.contentView)),
                             "Guide button is outside its panel")
            }
        }
        for window in [pending, allowed, drag] {
            window.contentView!.layoutSubtreeIfNeeded()
            precondition(!window.isVisible)
            window.close()
        }
        print("PASS \(expected): native language selection, permission states, interpolation, update error, drag hint width")
    }

    private static func buttons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }

    private static func fields(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
    }

    private static func strings(in view: NSView) -> [String] {
        let own = (view as? NSTextField).map { [$0.stringValue] } ??
                  (view as? NSButton).map { [$0.title] } ?? []
        return own + view.subviews.flatMap { strings(in: $0) }
    }
}
