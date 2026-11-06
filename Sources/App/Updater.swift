import AppKit

private final class UpdateNetworkPolicy: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    let source: UpdateSource
    init(source: UpdateSource) { self.source = source }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(source.accepts) == true ? request : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > 256 * 1024 * 1024 || totalBytesExpectedToWrite > 256 * 1024 * 1024 {
            downloadTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

/// Manual check -> consent -> download/verify -> atomic replacement -> restart in open state.
/// Never opens a curtain session in order to install an update.
@MainActor
final class Updater {
    var canUpdate: () -> Bool = { false }
    var onStateChange: (() -> Void)?
    private(set) var isBusy = false
    private var task: Task<Void, Never>?
    private var progress: UpdateProgressWindow?
    private var alert: NSAlert?
    private var terminationCompletion: (() -> Void)?

    func checkForUpdates() {
        guard !isBusy, canUpdate() else { return }
        isBusy = true
        onStateChange?()
        task = Task { [self] in
            var staging: URL?
            var installed = false
            defer {
                if !installed, let staging { try? FileManager.default.removeItem(at: staging) }
                progress?.close()
                progress = nil
                task = nil
                isBusy = false
                onStateChange?()
                let completion = terminationCompletion
                terminationCompletion = nil
                completion?()
            }
            var session: URLSession?
            defer { session?.invalidateAndCancel() }
            do {
                guard let api = infoURL("CurtainReleasesAPIURL"), let page = infoURL("CurtainReleasesPageURL"),
                      let current = AppVersion(currentVersionText) else { throw UpdateFailure.invalidRelease }
                let source = try UpdateSource(api: api, page: page)
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 15
                config.timeoutIntervalForResource = 180
                let network = URLSession(configuration: config, delegate: UpdateNetworkPolicy(source: source), delegateQueue: nil)
                session = network
                let window = UpdateProgressWindow()
                window.onCancel = { [weak self] in self?.cancel() }
                progress = window
                window.present()
                var request = URLRequest(url: source.api)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await network.data(for: request)
                try Task.checkCancellation()
                guard canUpdate() else { throw UpdateFailure.privacySession }
                if (response as? HTTPURLResponse)?.statusCode == 404 { throw UpdateFailure.noRelease }
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2 * 1024 * 1024,
                      response.url.map(source.accepts) == true else { throw UpdateFailure.network }
                let release = try UpdateRelease.parse(data, source: source)
                guard let version = AppVersion(release.tagName) else { throw UpdateFailure.invalidRelease }
                window.orderOut(nil)
                if version <= current {
                    _ = showAlert(title: String(localized: "Curtain Is Up to Date"), message: String(localized: "You have version \(currentVersionText)."), buttons: [String(localized: "OK")])
                    return
                }
                let notes = String((release.body ?? "").prefix(1600)).split(whereSeparator: \.isNewline).prefix(6).joined(separator: "\n")
                let choice = showAlert(title: String(localized: "Curtain \(version.description) Is Available"),
                                       message: String(localized: "You have version \(currentVersionText). Curtain will restart after installation.") + "\n\n" + notes,
                                       buttons: [String(localized: "Download and Install"), String(localized: "Later"), String(localized: "Open Release Page")])
                try Task.checkCancellation()
                if choice == .alertThirdButtonReturn { NSWorkspace.shared.open(URL(string: release.htmlUrl)!); return }
                guard choice == .alertFirstButtonReturn else { return }
                guard canUpdate() else { throw UpdateFailure.privacySession }
                let url = try release.packageURL(source: source)
                let app = Bundle.main.bundleURL
                try UpdatePackage.checkLocation(app)
                guard let team = UpdatePackage.currentTeamID else { throw UpdateFailure.untrusted }
                let directory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                            appropriateFor: app, create: true)
                staging = directory
                window.setStatus(String(localized: "Downloading Curtain \(version.description)…"))
                window.present()
                let (download, downloadResponse) = try await network.download(from: url)
                defer { try? FileManager.default.removeItem(at: download) }
                try Task.checkCancellation()
                guard (downloadResponse as? HTTPURLResponse)?.statusCode == 200,
                      downloadResponse.url.map(source.accepts) == true,
                      (try download.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 256 * 1024 * 1024 else {
                    throw UpdateFailure.network
                }
                let zip = directory.appendingPathComponent("Curtain.zip")
                try FileManager.default.moveItem(at: download, to: zip)
                window.setStatus(String(localized: "Verifying Update…"))
                let candidate = try await Task.detached {
                    let candidate = try UpdatePackage.unpack(zip, into: directory)
                    try UpdatePackage.verify(candidate, expected: version, current: current, team: team)
                    return candidate
                }.value
                try Task.checkCancellation()
                // Prepare the restart helper before the swap. It will do nothing unless the
                // atomic exchange succeeds and we explicitly arm it through its stdin pipe.
                let relaunch = try RelaunchAfterUpdate(app: app, staging: directory)
                do {
                    try UpdatePackage.exchange(app, with: candidate, permitted: canUpdate, afterSwap: relaunch.arm)
                } catch UpdateFailure.rollback {
                    installed = true // preserve the old bundle in staging if the OS refused rollback
                    relaunch.cancel()
                    throw UpdateFailure.rollback
                } catch {
                    relaunch.cancel()
                    throw error
                }
                installed = true
                window.setStatus(String(localized: "Restarting…"), cancellable: false)
                NSApp.terminate(nil)
            } catch {
                guard !Task.isCancelled else { return }
                progress?.orderOut(nil)
                let choice = showAlert(title: String(localized: "Could Not Update Curtain"), message: error.localizedDescription,
                                       buttons: [String(localized: "OK"), String(localized: "Open Release Page")])
                if choice == .alertSecondButtonReturn,
                   let api = infoURL("CurtainReleasesAPIURL"), let page = infoURL("CurtainReleasesPageURL"),
                   let source = try? UpdateSource(api: api, page: page) { NSWorkspace.shared.open(source.page) }
            }
        }
    }

    /// Quit waits for any filesystem work and staging cleanup, then replies to AppKit.
    /// Cancelling never forces open an active curtain and never arms the relaunch helper.
    func cancelForTermination(_ completion: @escaping () -> Void) -> Bool {
        guard isBusy else { return false }
        terminationCompletion = completion
        cancel()
        return true
    }

    private func cancel() {
        task?.cancel()
        if let alert {
            NSApp.abortModal()
            alert.window.orderOut(nil)
        }
        progress?.setStatus(String(localized: "Cancelling…"), cancellable: false)
    }

    private var currentVersionText: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    private func infoURL(_ key: String) -> URL? { (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap(URL.init(string:)) }

    private func showAlert(title: String, message: String, buttons: [String]) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        self.alert = alert
        NSApp.activate()
        let response = alert.runModal()
        self.alert = nil
        return response
    }
}

/// Reads an explicit commit signal before waiting for exit. EOF (failed/cancelled swap) exits
/// without touching the app or staging. Paths are positional arguments, never shell source.
private final class RelaunchAfterUpdate {
    private let process = Process()
    private let pipe = Pipe()

    init(app: URL, staging: URL) throws {
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", """
            IFS= read -r action || exit 0
            [ "$action" = restart ] || exit 0
            i=0
            while kill -0 "$1" 2>/dev/null; do
                i=$((i + 1))
                [ "$i" -ge 150 ] && exit 0
                sleep 0.2
            done
            /usr/bin/open "$2"
            /bin/rm -rf "$3"
            """, "curtain-update", String(getpid()), app.path, staging.path]
        process.standardInput = pipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        pipe.fileHandleForReading.closeFile()
    }

    func cancel() { pipe.fileHandleForWriting.closeFile() }
    func arm() throws {
        try pipe.fileHandleForWriting.write(contentsOf: Data("restart\n".utf8))
        pipe.fileHandleForWriting.closeFile()
    }
}

private final class UpdateProgressWindow: NSWindow {
    var onCancel: (() -> Void)?
    private let status = NSTextField(labelWithString: String(localized: "Checking for Updates…"))
    private let cancelButton = NSButton(title: String(localized: "Cancel"), target: nil, action: nil)

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 370, height: 120), styleMask: [.titled], backing: .buffered, defer: true)
        title = String(localized: "Curtain Update")
        isReleasedWhenClosed = false
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        let indicator = NSProgressIndicator()
        indicator.style = .bar
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        indicator.widthAnchor.constraint(equalToConstant: 320).isActive = true
        let stack = NSStackView(views: [status, indicator, cancelButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        contentView = stack
        setContentSize(stack.fittingSize)
    }

    func present() { center(); NSApp.activate(); makeKeyAndOrderFront(nil) }
    func setStatus(_ text: String, cancellable: Bool = true) { status.stringValue = text; cancelButton.isEnabled = cancellable }
    @objc private func cancelClicked() { onCancel?() }
}
