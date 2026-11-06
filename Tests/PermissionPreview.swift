import AppKit

/// Offscreen rendering of the production AppKit views. Does not open Settings, change TCC,
/// start CurtainController, install a tap or alter gamma. These are previews, not GUI acceptance.
@main
@MainActor
enum PermissionPreview {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let pending = PermissionWindow(trusted: false)
            let allowed = PermissionWindow(trusted: true)
            let drag = PermissionDragPanel()
            for (state, window) in [("ungranted", pending), ("granted", allowed), ("guide", drag)] {
                window.appearance = NSAppearance(named: appearance)
                try render(window, to: output.appendingPathComponent("\(state)-\(name).png"))
            }
            // Exercise live grant/revoke and reopen with the exact same window, then render.
            pending.setTrusted(true)
            try render(pending, to: output.appendingPathComponent("transition-granted-\(name).png"))
            pending.setTrusted(false)
            try render(pending, to: output.appendingPathComponent("transition-revoked-\(name).png"))
            let flight = PermissionLaunchAnimation(panel: drag,
                from: NSRect(x: 200, y: 500, width: 54, height: 24),
                to: NSRect(x: 500, y: 250, width: drag.frame.width, height: drag.frame.height))
            for (phase, elapsed) in [("start", 0.0), ("middle", 0.24), ("end", 0.72)] {
                flight.apply(elapsed: elapsed)
                try render(drag, to: output.appendingPathComponent("flight-\(phase)-\(name).png"))
            }
            let row = PermissionAppDragRow(frame: NSRect(x: 0, y: 0, width: 362, height: 44))
            row.appearance = NSAppearance(named: appearance)
            let image = row.makeDraggingItem().imageComponentsProvider?().first?.contents as? NSImage
            if let data = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: output.appendingPathComponent("drag-snapshot-\(name).png"))
            }
            pending.close()
            allowed.close()
            drag.close()
        }
        print("Rendered production permission views in light/dark; no visible windows or permission changes.")
    }

    private static func render(_ window: NSWindow, to url: URL) throws {
        guard let frame = window.contentView?.superview else { fatalError("No native window frame") }
        frame.layoutSubtreeIfNeeded()
        frame.displayIfNeeded()
        let size = frame.bounds.size
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
                                             pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("No bitmap") }
        bitmap.size = size
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
        try png.write(to: url)
        print("PREVIEW \(url.lastPathComponent) \(Int(size.width))×\(Int(size.height)) pt (2×)")
    }
}
