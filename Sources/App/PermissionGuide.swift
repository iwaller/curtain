import AppKit
import ApplicationServices
import QuartzCore

/// Read-only permission polling. A change never installs/removes a tap in an existing session.
@MainActor
final class AccessibilityPermissionMonitor {
    private let trusted: () -> Bool
    private(set) var isTrusted: Bool
    var onChange: ((Bool) -> Void)?
    private var timer: Timer?

    init(trusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.trusted = trusted
        isTrusted = trusted()
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        let value = trusted()
        guard value != isTrusted else { return }
        isTrusted = value
        onChange?(value)
    }

    func stop() { timer?.invalidate(); timer = nil }
}

/// The main card and the Settings drag strip are separate surfaces, as in Barlet.
/// Polling may update/dismiss them, but never activates a window or changes an input tap.
@MainActor
final class PermissionGuide: NSObject, NSWindowDelegate {
    var canPresent: () -> Bool = { false }
    var isVisible: Bool { window?.isVisible == true || dragGuide.isVisible }
    private var window: PermissionWindow?
    private let dragGuide: SettingsDragGuide
    private var trusted = false

    init(openSettings: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        dragGuide = SettingsDragGuide(openSettings: openSettings)
        super.init()
        dragGuide.onBack = { [weak self] in
            guard let self, self.canPresent() else { return }
            self.show(trusted: self.trusted)
        }
    }

    func show(trusted: Bool) {
        guard canPresent() else { return }
        dragGuide.dismiss()
        let window = self.window ?? makeWindow(trusted: trusted)
        refresh(trusted: trusted)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func refresh(trusted: Bool) {
        self.trusted = trusted
        window?.setTrusted(trusted)
        if trusted { dragGuide.dismiss() }
    }

    func dismiss() {
        window?.orderOut(nil)
        dragGuide.dismiss()
    }

    func windowWillClose(_ notification: Notification) { dragGuide.dismiss() }

    private func makeWindow(trusted: Bool) -> PermissionWindow {
        let window = PermissionWindow(trusted: trusted)
        window.delegate = self
        window.onAllow = { [weak self] source in
            guard let self, self.canPresent(), !self.trusted else { return }
            // Opening Settings is only ever a direct response to the Allow button.
            _ = self.dragGuide.present(from: source)
        }
        self.window = window
        return window
    }
}

/// A fixed-width, compact native card. Constructors are shared with the isolated render tool;
/// the preview renders these actual views, rather than reimplementing their layout.
@MainActor
final class PermissionWindow: NSWindow {
    var onAllow: ((CGRect) -> Void)?
    private let permissionRow = PermissionRow()
    private let heading = NSTextField(labelWithString: String(localized: "Set Up Curtain"))
    private let note = PermissionWindow.wrappingLabel("")
    private let doneButton = NSButton()

    init(trusted: Bool) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
                   styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        title = String(localized: "Curtain Permissions")
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        heading.font = .systemFont(ofSize: 20, weight: .bold)
        let body = Self.wrappingLabel(String(localized: "Block keyboard and mouse input while the privacy screen is on."))
        body.font = .systemFont(ofSize: 13)
        permissionRow.onAllow = { [weak self] source in self?.onAllow?(source) }
        permissionRow.widthAnchor.constraint(equalToConstant: 376).isActive = true
        permissionRow.heightAnchor.constraint(equalToConstant: 68).isActive = true
        note.font = .systemFont(ofSize: 11)
        doneButton.bezelStyle = .push
        doneButton.controlSize = .large
        doneButton.target = self
        doneButton.action = #selector(doneClicked)
        let stack = NSStackView(views: [icon, heading, body, permissionRow, note, doneButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(22, after: body)
        stack.setCustomSpacing(14, after: permissionRow)
        stack.setCustomSpacing(18, after: note)
        stack.edgeInsets = NSEdgeInsets(top: 36, left: 32, bottom: 24, right: 32)
        stack.widthAnchor.constraint(equalToConstant: 440).isActive = true
        contentView = stack
        setTrusted(trusted)
        setContentSize(NSSize(width: 440, height: ceil(stack.fittingSize.height)))
        center()
    }

    func setTrusted(_ trusted: Bool) {
        permissionRow.setTrusted(trusted)
        heading.stringValue = trusted ? String(localized: "You're All Set") : String(localized: "Set Up Curtain")
        note.stringValue = trusted ? String(localized: "Applies the next time you enable the privacy screen.") : String(localized: "Without this permission, the screen is hidden but local input is not blocked.")
        doneButton.title = trusted ? String(localized: "Done") : String(localized: "Not Now")
        doneButton.keyEquivalent = trusted ? "\r" : "\u{1b}"
        // Translations can wrap differently when permission is granted or revoked.
        if let contentView {
            setContentSize(NSSize(width: 440, height: ceil(contentView.fittingSize.height)))
        }
    }

    @objc private func doneClicked() { close() }

    private static func wrappingLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.alignment = .center
        label.isSelectable = false
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 376
        label.widthAnchor.constraint(equalToConstant: 376).isActive = true
        return label
    }
}

@MainActor
private final class PermissionRow: NSView {
    var onAllow: ((CGRect) -> Void)?
    private let allow = NSButton(title: String(localized: "Allow"), target: nil, action: nil)
    private let allowed = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 0.5
        let symbol = NSImageView(image: NSImage(systemSymbolName: "accessibility", accessibilityDescription: nil) ?? NSImage())
        symbol.symbolConfiguration = .init(pointSize: 24, weight: .regular)
        symbol.contentTintColor = .controlAccentColor
        let name = NSTextField(labelWithString: Self.permissionName)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        let purpose = NSTextField(labelWithString: String(localized: "Block physical keyboard and mouse input"))
        purpose.font = .systemFont(ofSize: 11)
        purpose.textColor = .secondaryLabelColor
        let texts = NSStackView(views: [name, purpose])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 3
        allow.bezelStyle = .push
        allow.target = self
        allow.action = #selector(allowClicked)
        let check = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) ?? NSImage())
        check.contentTintColor = .systemGreen
        let text = NSTextField(labelWithString: String(localized: "Allowed"))
        text.font = .systemFont(ofSize: 12, weight: .medium)
        text.textColor = .secondaryLabelColor
        allowed.setViews([text, check], in: .leading)
        allowed.spacing = 5
        [symbol, texts, allow, allowed].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 32),
            symbol.heightAnchor.constraint(equalToConstant: 30),
            texts.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 12),
            texts.centerYAnchor.constraint(equalTo: centerYAnchor),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -96),
            allow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            allow.centerYAnchor.constraint(equalTo: centerYAnchor),
            allowed.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            allowed.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 16),
            check.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private static var permissionName: String {
        if #available(macOS 27, *) { return String(localized: "Device Control and Data Access") }
        return String(localized: "Accessibility")
    }
    func setTrusted(_ trusted: Bool) { allow.isHidden = trusted; allowed.isHidden = !trusted }
    @objc private func allowClicked() {
        guard let window else { return }
        onAllow?(window.convertToScreen(allow.convert(allow.bounds, to: nil)))
    }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}

/// A small strip over the bottom of System Settings. No AX permission is needed to read its
/// window bounds. Only the frontmost Settings app is followed; all timers/observers are scoped
/// to this flow. The strip launches from the Allow button, following Barlet's spring/arc.
@MainActor
private final class SettingsDragGuide {
    var onBack: (() -> Void)?
    var isVisible: Bool { panel?.isVisible == true }
    private var panel: PermissionDragPanel?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var startedAt = Date.distantPast
    private var launchSource: CGRect?
    private var launch: PermissionLaunchAnimation?
    private var draggingApp = false
    private nonisolated static let settingsID = "com.apple.systempreferences"
    private let openSettings: (URL) -> Bool

    init(openSettings: @escaping (URL) -> Bool) { self.openSettings = openSettings }

    func present(from source: CGRect) -> Bool {
        dismiss()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
              openSettings(url) else { return false }
        let panel = PermissionDragPanel()
        panel.onBack = { [weak self] in
            guard let self else { return }
            self.dismiss()
            self.onBack?()
        }
        panel.onDraggingApp = { [weak self, weak panel] dragging in
            guard let self, let panel else { return }
            self.draggingApp = dragging
            if dragging {
                self.timer?.invalidate()
                self.timer = nil
                if let animation = self.launch {
                    animation.stop()
                    panel.setFrameOrigin(animation.target.origin)
                    panel.setContentScale(1)
                    panel.alphaValue = 1
                    self.launch = nil
                }
            } else { self.tick() }
        }
        self.panel = panel
        launchSource = source
        startedAt = Date()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == Self.settingsID { MainActor.assumeIsolated { self?.dismiss() } }
        })
        tick()
        return true
    }

    func dismiss() {
        launch?.stop()
        launch = nil
        launchSource = nil
        draggingApp = false
        timer?.invalidate()
        timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        panel?.orderOut(nil)
        panel = nil
    }

    private func tick() {
        timer?.invalidate()
        timer = nil
        guard let panel else { return }
        guard !draggingApp else { return }
        guard let settings = NSWorkspace.shared.frontmostApplication, settings.bundleIdentifier == Self.settingsID else {
            launch?.stop()
            launch = nil
            panel.orderOut(nil)
            if Date().timeIntervalSince(startedAt) < 5 { schedule(after: 0.1) }
            return
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let frames = windows.compactMap { entry -> CGRect? in
            guard entry[kCGWindowOwnerPID as String] as? Int32 == settings.processIdentifier,
                  entry[kCGWindowLayer as String] as? Int == 0,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.width > 320, frame.height > 240 else { return nil }
            return frame
        }
        if let global = frames.max(by: { $0.width * $0.height < $1.width * $1.height }) {
            // CG coordinates use a top-left origin on the primary display; Cocoa uses bottom-left.
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            let settingsFrame = NSRect(x: global.minX, y: primaryTop - global.maxY, width: global.width, height: global.height)
            let visible = (NSScreen.screens.first { $0.frame.intersects(settingsFrame) } ?? NSScreen.main)?.visibleFrame ?? settingsFrame
            let size = panel.frame.size
            let x = settingsFrame.maxX - size.width - 16
            let y = settingsFrame.minY + 44
            let target = NSRect(x: max(visible.minX + 8, min(x, visible.maxX - size.width - 8)),
                                y: max(visible.minY + 8, min(y, visible.maxY - size.height - 8)),
                                width: size.width, height: size.height)
            if let launch {
                launch.target = target
            } else if let source = launchSource, !source.isEmpty {
                launchSource = nil
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    panel.setFrameOrigin(target.origin)
                    panel.setContentScale(1)
                    panel.alphaValue = 1
                    panel.orderFrontRegardless()
                } else {
                    let animation = PermissionLaunchAnimation(panel: panel, from: source, to: target)
                    animation.onFinish = { [weak self] in self?.launch = nil }
                    launch = animation
                    animation.start()
                }
            } else {
                panel.setFrameOrigin(target.origin)
                panel.setContentScale(1)
                panel.alphaValue = 1
                panel.orderFrontRegardless()
            }
        } else {
            launch?.stop()
            launch = nil
            panel.orderOut(nil)
            if Date().timeIntervalSince(startedAt) < 5 { schedule(after: 0.1) }
            return
        }
        schedule()
    }

    private func schedule(after interval: TimeInterval = 0.5) {
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

/// Short-lived display-link driver, with the same 0.72 s critically damped spring and curved
/// trajectory as Barlet. Content scales inside a fixed-size window, avoiding layout squeeze.
@MainActor
final class PermissionLaunchAnimation: NSObject {
    var target: CGRect
    var onFinish: (() -> Void)?
    private static let duration: CFTimeInterval = 0.72
    private weak var panel: PermissionDragPanel?
    private let source: CGRect
    private var startedAt: CFTimeInterval = 0
    private var displayLink: CADisplayLink?

    init(panel: PermissionDragPanel, from source: CGRect, to target: CGRect) {
        self.panel = panel
        self.source = source
        self.target = target
    }

    func start() {
        stop()
        guard let panel else { return }
        startedAt = CACurrentMediaTime()
        apply(elapsed: 0)
        panel.orderFrontRegardless()
        let link = panel.displayLink(target: self, selector: #selector(frameFired(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func frameFired(_ link: CADisplayLink) {
        guard displayLink != nil else { return }
        if apply(elapsed: CACurrentMediaTime() - startedAt) {
            stop()
            onFinish?()
        }
    }

    /// Also used by the native render tool to capture actual animation poses offscreen.
    @discardableResult
    func apply(elapsed: CFTimeInterval) -> Bool {
        guard let panel else { return true }
        let elapsed = max(0, elapsed)
        let omega = 2 * Double.pi / Self.duration
        let t: CGFloat = elapsed >= Self.duration ? 1 : CGFloat(min(1, 1 - exp(-omega * elapsed) * (1 + omega * elapsed)))
        let u = 1 - t
        let from = CGPoint(x: source.midX, y: source.midY)
        let to = CGPoint(x: target.midX, y: target.midY)
        let lift = min(140, max(44, hypot(to.x - from.x, to.y - from.y) * 0.18))
        let control = CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + lift)
        let center = CGPoint(x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                             y: u * u * from.y + 2 * u * t * control.y + t * t * to.y)
        let initialScale = min(1, max(0.2, source.width / target.width))
        panel.setContentScale(initialScale + (1 - initialScale) * t)
        panel.alphaValue = 0.6 + 0.4 * t
        panel.setFrameOrigin(CGPoint(x: center.x - target.width / 2, y: center.y - target.height / 2))
        return elapsed >= Self.duration
    }
}

@MainActor
final class PermissionDragPanel: NSPanel {
    var onBack: (() -> Void)?
    var onDraggingApp: ((Bool) -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 104),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        animationBehavior = .none
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 440, height: 104))
        background.material = .popover
        background.blendingMode = .withinWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true
        let back = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: String(localized: "Back to Permissions")) ?? NSImage(), target: self, action: #selector(backClicked))
        back.bezelStyle = .circular
        back.frame = NSRect(x: 16, y: 20, width: 30, height: 30)
        back.setAccessibilityLabel(String(localized: "Back to Permissions"))
        let arrow = NSImageView(image: NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil) ?? NSImage())
        arrow.symbolConfiguration = .init(pointSize: 21, weight: .bold)
        arrow.contentTintColor = .controlAccentColor
        arrow.frame = NSRect(x: 60, y: 66, width: 24, height: 26)
        let hint = NSTextField(labelWithString: String(localized: "Drag Curtain into the list above, or turn it on."))
        hint.font = .systemFont(ofSize: 13, weight: .medium)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 94, y: 68, width: 328, height: 22)
        let row = PermissionAppDragRow(frame: NSRect(x: 60, y: 13, width: 362, height: 44))
        row.onDragging = { [weak self] dragging in self?.onDraggingApp?(dragging) }
        let root = NSView(frame: background.frame)
        root.wantsLayer = true
        root.addSubview(background)
        [back, arrow, hint, row].forEach(background.addSubview)
        contentView = root
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    func setContentScale(_ scale: CGFloat) {
        guard let layer = contentView?.layer else { return }
        let size = frame.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setAffineTransform(CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                                 tx: (1 - scale) * size.width / 2,
                                                 ty: (1 - scale) * size.height / 2))
        CATransaction.commit()
        invalidateShadow()
    }
    @objc private func backClicked() { onBack?() }
}

final class PermissionAppDragRow: NSView, NSDraggingSource {
    var onDragging: ((Bool) -> Void)?
    private var down: NSEvent?
    private var dragImage: NSImage?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.frame = NSRect(x: 12, y: 9, width: 26, height: 26)
        let title = NSTextField(labelWithString: "Curtain")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.frame = NSRect(x: 48, y: 12, width: 200, height: 20)
        addSubview(icon)
        addSubview(title)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        setAccessibilityLabel(String(localized: "Drag Curtain into the permissions list."))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = NSColor.white.withAlphaComponent(dark ? 0.08 : 0.7).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        dragImage = nil
    }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { NSCursor.openHand.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
    override func mouseDown(with event: NSEvent) {
        down = event
        if dragImage == nil { dragImage = snapshot() }
        NSCursor.closedHand.set()
    }
    override func mouseUp(with event: NSEvent) { down = nil; NSCursor.openHand.set() }
    override func mouseDragged(with event: NSEvent) {
        guard let down else { return }
        self.down = nil
        let item = makeDraggingItem()
        beginDraggingSession(with: [item], event: down, source: self).animatesToStartingPositionsOnCancelOrFail = true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func makeDraggingItem() -> NSDraggingItem {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: dragImage ?? snapshot())
        return item
    }
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        alphaValue = 0
        onDragging?(true)
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        alphaValue = 1
        NSCursor.openHand.set()
        onDragging?(false)
    }
    private func snapshot() -> NSImage {
        let image = NSImage(size: bounds.size)
        if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: bitmap)
            image.addRepresentation(bitmap)
        }
        return image
    }
}
