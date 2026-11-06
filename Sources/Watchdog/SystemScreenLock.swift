import Foundation
import CoreGraphics
import Darwin

/// Runtime-only private system entry point. No keyboard injection, AppleScript or security-setting changes.
enum SystemScreenLock {
    private static let library = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY)
    private static let entry = library.flatMap { dlsym($0, "SACLockScreenImmediate") }
    static var isAvailable: Bool { entry != nil }

    static func request() {
        guard let entry else { return }
        // Run in a separate process: even a stuck system call cannot stall the watchdog's deadline.
        let lock = unsafeBitCast(entry, to: (@convention(c) () -> Int32).self)
        let result = lock()
        watchdogLog("lock-request result=\(result)")
    }

    static var isLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
    }

    static var isOnConsole: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?[kCGSessionOnConsoleKey as String] as? Bool == true
    }
}

