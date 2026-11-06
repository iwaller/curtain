import AppKit
import Darwin

struct Configuration {
    var duration: TimeInterval = 90
    var excludeCapture = false
    var noOverlay = false
    var gamma = false

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--duration":
                index += 1
                guard index < arguments.count,
                      let value = Double(arguments[index]), value.isFinite,
                      (1...300).contains(value) else {
                    throw ArgumentError.invalid("--duration must be between 1 and 300 seconds")
                }
                duration = value
            case "--exclude-capture": excludeCapture = true
            case "--no-overlay": noOverlay = true
            case "--gamma": gamma = true
            default: throw ArgumentError.invalid("Unknown argument: \(arguments[index])")
            }
            index += 1
        }
        if gamma && (excludeCapture || noOverlay) {
            throw ArgumentError.invalid("--gamma cannot be combined with --exclude-capture or --no-overlay")
        }
    }
}

enum ArgumentError: Error { case invalid(String) }

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController: NSObject, NSApplicationDelegate {
    private let configuration: Configuration
    private var windows: [NSWindow] = []
    private var gammaBlackout: GammaBlackout?
    private var timeout: Timer?
    private var signals: [DispatchSourceSignal] = []
    private var screenObserver: NSObjectProtocol?
    private var stopping = false
    private var cleanedUp = false

    init(configuration: Configuration) { self.configuration = configuration }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Install every exit path before creating any covering window.
        timeout = Timer.scheduledTimer(withTimeInterval: configuration.duration, repeats: false) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.stop(reason: "timeout") }
        }
        // Agents often launch the POC from a short-lived shell; do not die with it.
        signal(SIGHUP, SIG_IGN)
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.stop(reason: "signal \(number)") }
            }
            source.resume()
            signals.append(source)
        }
        log("started pid=\(getpid()) duration=\(configuration.duration) mode=\(configuration.gamma ? "gamma" : configuration.excludeCapture ? "exclude-capture" : "ordinary") noOverlay=\(configuration.noOverlay)")
        if configuration.gamma {
            let blackout = GammaBlackout()
            gammaBlackout = blackout
            blackout.start()
        } else if !configuration.noOverlay {
            rebuildWindows()
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildWindows() }
            }
        }
    }

    private func rebuildWindows() {
        let oldWindows = windows
        windows = NSScreen.screens.enumerated().map { index, screen in
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless,
                                       backing: .buffered, defer: false)
            window.title = "Curtain POC \(index + 1)"
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.sharingType = configuration.excludeCapture ? .none : .readOnly
            window.orderFrontRegardless()
            log("screen=\(index + 1) frame=\(NSStringFromRect(screen.frame)) scale=\(screen.backingScaleFactor) window=\(window.windowNumber) level=\(window.level.rawValue)")
            return window
        }
        oldWindows.forEach { $0.close() }
        log("overlays-visible count=\(windows.count)")
    }

    private func stop(reason: String) {
        guard !stopping else { return }
        stopping = true
        log("stopping reason=\(reason)")
        cleanup()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) { cleanup() }

    private func cleanup() {
        guard !cleanedUp else { return }
        cleanedUp = true
        timeout?.invalidate()
        timeout = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        windows.forEach { $0.close() }
        windows.removeAll()
        gammaBlackout?.stop()
        gammaBlackout = nil
        signals.forEach { $0.cancel() }
        signals.removeAll()
        log("cleanup-complete windows=0")
    }
}

if CommandLine.arguments.contains("--help") {
    print("Usage: curtain [--duration 1...300] [--exclude-capture | --gamma] [--no-overlay]")
    print("--gamma: zero display gamma instead of covering windows; restored on exit.")
    print("Default timeout: 90 seconds. Stop from another terminal: kill -TERM <pid>.")
    exit(0)
}

do {
    let configuration = try Configuration(arguments: Array(CommandLine.arguments.dropFirst()))
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let controller = OverlayController(configuration: configuration)
        application.delegate = controller
        application.run()
        withExtendedLifetime(controller) {}
    }
} catch ArgumentError.invalid(let message) {
    fputs("\(message)\n", stderr)
    exit(2)
} catch {
    fputs("\(error)\n", stderr)
    exit(2)
}
