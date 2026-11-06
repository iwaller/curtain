/// Protocol is deliberately tiny; a graceful disarm takes precedence over queued heartbeats.
/// EOF is not a graceful disarm: a living parent with a broken channel needs recovery.
struct HeartbeatDeadline {
    let timeout: UInt64
    private(set) var lastBeat: UInt64
    private(set) var disarmed = false

    init(now: UInt64, timeout: UInt64 = 10_000_000_000) {
        lastBeat = now
        self.timeout = timeout
    }

    mutating func receive(_ bytes: [UInt8], now: UInt64) -> Bool {
        guard bytes.allSatisfy({ $0 == 72 || $0 == 68 }) else { return false }
        if bytes.contains(68) { disarmed = true }
        if bytes.contains(72) { lastBeat = now }
        return true
    }

    func expired(at now: UInt64) -> Bool { now >= lastBeat && now - lastBeat >= timeout }
}

