import AppKit
import ApplicationServices

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

/// Explains the purpose first; opens Settings only on an explicit click. No simultaneous AX
/// system prompt. The draggable file URL re-registers the current signed app in Settings.
@MainActor
final class PermissionGuide: NSObject, NSWindowDelegate {
    var canPresent: () -> Bool = { false }
    private(set) var isVisible = false
    private var window: NSWindow?
    private let status = NSTextField(labelWithString: "")
    private let allow = NSButton(title: "打开系统设置…", target: nil, action: nil)

    func show(trusted: Bool) {
        guard canPresent() else { return }
        if window == nil { makeWindow() }
        refresh(trusted: trusted)
        isVisible = true
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func refresh(trusted: Bool) {
        // Never bring UI forward in response to a polling event.
        status.stringValue = trusted ? "辅助功能：已允许 · 下次拉上幕布时生效" : "辅助功能：尚未允许"
        allow.isEnabled = !trusted
    }

    func dismiss() { window?.orderOut(nil); isVisible = false }
    func windowWillClose(_ notification: Notification) { isVisible = false }

    @objc private func openSettings() {
        guard canPresent(), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func done() { dismiss() }

    private func makeWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Curtain 权限设置"
        window.isReleasedWhenClosed = false
        window.delegate = self
        // Keep the app drag row reachable while System Settings is in front, like Barlet's guide.
        window.level = .floating
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let title = NSTextField(labelWithString: "允许 Curtain 拦截本地输入")
        title.font = .systemFont(ofSize: 19, weight: .semibold)
        let body = label("辅助功能权限用于在幕布拉上时拦截实体键盘、鼠标和触控板，并唤出解锁界面。不会申请屏幕录制权限。")
        status.font = .systemFont(ofSize: 12, weight: .medium)
        allow.target = self
        allow.action = #selector(openSettings)
        allow.bezelStyle = .rounded
        let hint = label("打开设置后，将下方 Curtain 拖入辅助功能列表并开启开关。若已开启但无效，可移除旧条目后重新拖入。")
        let row = PermissionAppDragRow(frame: NSRect(x: 0, y: 0, width: 380, height: 44))
        row.widthAnchor.constraint(equalToConstant: 380).isActive = true
        row.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let foot = label("可暂不授权：仍能遮挡画面，但不会拦截本地输入。授权变化在下次拉上幕布时生效。")
        foot.textColor = .secondaryLabelColor
        let done = NSButton(title: "完成 / 稍后设置", target: self, action: #selector(done))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let stack = NSStackView(views: [icon, title, body, status, allow, hint, row, foot, done])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 30, bottom: 24, right: 30)
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        window.center()
        self.window = window
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.preferredMaxLayoutWidth = 380
        label.widthAnchor.constraint(equalToConstant: 380).isActive = true
        label.alignment = .center
        label.font = .systemFont(ofSize: 12)
        return label
    }
}

private final class PermissionAppDragRow: NSView, NSDraggingSource {
    private var down: NSEvent?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
        icon.frame = NSRect(x: 12, y: 6, width: 32, height: 32)
        let title = NSTextField(labelWithString: "Curtain.app — 拖入权限列表")
        title.frame = NSRect(x: 56, y: 13, width: 310, height: 20)
        addSubview(icon)
        addSubview(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { down = event }
    override func mouseUp(with event: NSEvent) { down = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let down else { return }
        self.down = nil
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48),
                              contents: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
        beginDraggingSession(with: [item], event: down, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
