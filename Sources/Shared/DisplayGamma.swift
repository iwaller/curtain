import CoreGraphics

/// The display pipeline boundary; tests supply independent tables for multiple simulated displays.
@MainActor
protocol DisplayGamma {
    func onlineDisplays() -> [CGDirectDisplayID]?
    func setBlack(_ display: CGDirectDisplayID) -> CGError
    func isBlack(_ display: CGDirectDisplayID) -> Bool
    func restore()
}

struct SystemDisplayGamma: DisplayGamma {
    private static let tableSize: UInt32 = 256
    private let zeros = [CGGammaValue](repeating: 0, count: Int(tableSize))

    func onlineDisplays() -> [CGDirectDisplayID]? {
        // Online includes attached displays in a mirror set; active alone can omit them.
        for _ in 0..<2 {
            var capacity: UInt32 = 0
            guard CGGetOnlineDisplayList(0, nil, &capacity) == .success, capacity > 0 else { return nil }
            var displays = [CGDirectDisplayID](repeating: 0, count: Int(capacity))
            var count: UInt32 = 0
            let result = CGGetOnlineDisplayList(capacity, &displays, &count)
            if count > capacity { continue } // Configuration changed between the two reads.
            guard result == .success, count > 0 else { return nil }
            return Array(displays.prefix(Int(count)))
        }
        return nil
    }

    func setBlack(_ display: CGDirectDisplayID) -> CGError {
        CGSetDisplayTransferByTable(display, Self.tableSize, zeros, zeros, zeros)
    }

    func isBlack(_ display: CGDirectDisplayID) -> Bool {
        var red = [CGGammaValue](repeating: 1, count: Int(Self.tableSize))
        var green = red, blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, Self.tableSize, &red, &green, &blue, &count) == .success,
              count > 0, count <= Self.tableSize else { return false }
        let n = Int(count)
        return (red.prefix(n) + green.prefix(n) + blue.prefix(n)).allSatisfy { $0 < 0.001 }
    }

    func restore() { CGDisplayRestoreColorSyncSettings() }
}
