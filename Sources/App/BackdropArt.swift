import AppKit

/// Blurred, dimmed copy of the desktop wallpaper for the unlock screen, in the style of the
/// macOS 26 lock screen. Only the wallpaper is shown, never windows. Rendering a 4K/6K picture
/// takes a moment, so it is prepared when the curtain closes and cached for that session.
@MainActor
enum BackdropArt {
    private static var cache: [String: CGImage] = [:]
    private static var pending: [String: BackdropRenderJob] = [:]
    private static var generation: UInt64 = 0
    // Avoid simultaneous wallpaper decodes on multi-display setups.
    private static let renderQueue = DispatchQueue(label: "local.zjf.curtain.backdrop", qos: .utility,
                                                   autoreleaseFrequency: .workItem)

    /// Starts rendering art for every screen that has no cached image yet.
    static func prepare() {
        for screen in NSScreen.screens {
            guard let (key, url, size) = request(for: screen), cache[key] == nil, pending[key] == nil else { continue }
            let job = BackdropRenderJob()
            pending[key] = job
            let generation = generation
            renderQueue.async {
                let started = Date()
                let image = job.render(url: url, size: size)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard generation == Self.generation else { return }
                        pending.removeValue(forKey: key)
                        if let image { cache[key] = image }
                        log("backdrop-art \(image == nil ? "failed" : "ready") \(url.lastPathComponent) \(Int(size.width))x\(Int(size.height)) ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                    }
                }
            }
        }
    }

    /// Release art on return to open, including results still being rendered for the old session.
    static func clear() {
        generation &+= 1
        cache.removeAll()
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
    }

    /// The cached art for `screen`, or nil (callers fall back to a dark gradient).
    static func image(for screen: NSScreen) -> CGImage? {
        guard let (key, _, _) = request(for: screen) else { return nil }
        return cache[key]
    }

    private static func request(for screen: NSScreen) -> (String, URL, CGSize)? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        // Half the point size is plenty for a heavily blurred image.
        let size = CGSize(width: (screen.frame.width / 2).rounded(), height: (screen.frame.height / 2).rounded())
        return ("\(url.path)|\(size.width)x\(size.height)", url, size)
    }
}

/// Fills its bounds with an aspect-filled image, or a dark gradient when there is none,
/// plus a dimming layer so white text stays readable.
final class BackdropArtView: NSView {
    private let image: CGImage?
    /// Only these fill the view; subview layers (the clock) must keep their own frames.
    private var fillLayers: [CALayer] = []

    init(image: CGImage?) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func makeBackingLayer() -> CALayer {
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        if let image {
            root.contents = image
            root.contentsGravity = .resizeAspectFill
        } else {
            let gradient = CAGradientLayer()
            gradient.colors = [NSColor(red: 0.16, green: 0.18, blue: 0.26, alpha: 1).cgColor,
                               NSColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1).cgColor]
            gradient.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            root.addSublayer(gradient)
            fillLayers.append(gradient)
        }
        let dim = CALayer()
        dim.backgroundColor = NSColor(white: 0, alpha: 0.28).cgColor
        dim.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        root.addSublayer(dim)
        fillLayers.append(dim)
        return root
    }

    override func layout() {
        super.layout()
        fillLayers.forEach { $0.frame = bounds }
    }

    override func updateLayer() {}
}
