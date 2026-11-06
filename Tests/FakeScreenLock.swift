import Foundation

// Linked only into the test helper. The production helper has no switch to skip real locking.
enum SystemScreenLock {
    static var isAvailable: Bool { ProcessInfo.processInfo.environment["CURTAIN_TEST_LOCK_AVAILABLE"] != "0" }
    static var isOnConsole: Bool { true }
    static var isLocked: Bool {
        FileManager.default.fileExists(atPath: ProcessInfo.processInfo.environment["CURTAIN_TEST_LOCK_MARKER"]!)
    }
    static func request() {
        switch ProcessInfo.processInfo.environment["CURTAIN_TEST_LOCK_RESULT"] {
        case "locked":
            FileManager.default.createFile(atPath: ProcessInfo.processInfo.environment["CURTAIN_TEST_LOCK_MARKER"]!, contents: nil)
        case "hung": Thread.sleep(forTimeInterval: 120)
        default: break
        }
    }
}
