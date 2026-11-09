import AppKit

/// Native component regression, not Computer Use GUI/real TCC acceptance. Only test-owned
/// windows are shown briefly; System Settings is replaced by an inert opener.
@main
@MainActor
enum PermissionInteractionTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task {
            do {
                try await run()
                print("All permission interaction regressions passed")
                NSApp.terminate(nil)
            } catch { fatalError("Permission interaction regression: \(error)") }
        }
        app.run()
    }

    private static func run() async throws {
        let app = NSApplication.shared
        var opened = 0
        let guide = PermissionGuide(openSettings: { _ in opened += 1; return true })
        guide.canPresent = { true }
        guide.show(trusted: false)
        guard let window = app.windows.first(where: { $0 is PermissionWindow && $0.isVisible }),
              let content = window.contentView,
              let allow = buttons(in: content).first(where: { $0.title == String(localized: "Allow") }) else { fatalError("No permission card") }
        allow.performClick(nil)
        precondition(opened == 1 && window.isVisible, "Allow must retain the main window")
        print("PASS native Allow action opens the injected Settings endpoint without hiding the main window")
        guide.dismiss()
        precondition(!window.isVisible && !guide.isVisible)
        guide.canPresent = { false }
        allow.performClick(nil)
        precondition(opened == 1, "A stale button must not open Settings during privacy/update")
        print("PASS dismiss cleans the flow; stale Allow is rejected when presentation is forbidden")

        let smallScreen = CGRect(x: 0, y: 54, width: 1024, height: 690)
        let crowdedSettings = CGRect(x: 183, y: 102, width: 740, height: 625)
        let compact = PermissionGuidePlacement(settings: crowdedSettings, visible: smallScreen)
        let switches = CGRect(x: 800, y: 120, width: 110, height: 500)
        precondition(compact.compact && smallScreen.contains(compact.frame))
        precondition(!compact.frame.intersects(switches), "Crowded layout must leave the switches accessible")
        for screen in [CGRect(x: 0, y: 50, width: 1920, height: 1000),
                       CGRect(x: -1920, y: -300, width: 1920, height: 1000)] {
            let settings = CGRect(x: screen.minX + 500, y: screen.minY + 220, width: 740, height: 620)
            let placement = PermissionGuidePlacement(settings: settings, visible: screen)
            precondition(!placement.compact && screen.contains(placement.frame))
            precondition(!placement.frame.intersects(settings), "Roomy layout must stay outside Settings")
        }
        print("PASS placement leaves crowded-screen switches accessible and stays outside Settings when space permits")

        let panel = PermissionDragPanel()
        panel.setFrameOrigin(NSPoint(x: 300, y: 300))
        let row = PermissionAppDragRow(frame: NSRect(x: 0, y: 0, width: 362, height: 44))
        let item = row.makeDraggingItem()
        precondition(item.draggingFrame == row.bounds && item.item as? NSURL == Bundle.main.bundleURL as NSURL)
        guard let image = item.imageComponentsProvider?().first?.contents as? NSImage else { fatalError("No row snapshot") }
        precondition(image.size == row.bounds.size)
        print("PASS dragging item carries the app file URL and full row snapshot at its original bounds")

        let source = NSRect(x: 350, y: 550, width: 54, height: 24)
        let target = NSRect(x: 600, y: 260, width: panel.frame.width, height: panel.frame.height)
        let animation = PermissionLaunchAnimation(panel: panel, from: source, to: target)
        var completions = 0
        animation.onFinish = { completions += 1 }
        animation.start()
        let first = panel.frame.origin
        try await Task.sleep(for: .milliseconds(160))
        precondition(panel.frame.origin != first, "Display link did not advance")
        try await Task.sleep(for: .milliseconds(780))
        precondition(completions == 1 && hypot(panel.frame.minX - target.minX, panel.frame.minY - target.minY) < 2)
        precondition(panel.alphaValue == 1 && panel.contentView?.layer?.affineTransform() == .identity)
        panel.orderOut(nil)
        print("PASS real display-link flight advances, completes once, and restores full scale/opacity at target")
        animation.start()
        animation.stop()
        let stopped = panel.frame.origin
        try await Task.sleep(for: .milliseconds(200))
        precondition(panel.frame.origin == stopped && completions == 1)
        panel.close()
        window.close()
        print("PASS stopped flight cannot keep moving or deliver a late completion; temporary windows cleaned")
    }

    private static func buttons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }
}
