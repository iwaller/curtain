import Foundation
import CoreGraphics

// Backend-only injection into the production CLI; no display table is read or changed.
@MainActor
final class CLIFailingGamma: DisplayGamma {
    let mode = ProcessInfo.processInfo.environment["CURTAIN_TEST_GAMMA_FAILURE"]!
    var enumerations = 0
    var black: Set<CGDirectDisplayID> = []
    func onlineDisplays() -> [CGDirectDisplayID]? {
        enumerations += 1
        if mode == "runtime" && enumerations > 1 { return nil }
        return [1, 2]
    }
    func setBlack(_ display: CGDirectDisplayID) -> CGError {
        if mode == "initial" && display == 2 { return .failure }
        black.insert(display)
        return .success
    }
    func isBlack(_ display: CGDirectDisplayID) -> Bool { black.contains(display) }
    func restore() { black.removeAll(); print("CLI_BACKEND_RESTORED") }
}

@MainActor
func makeRegressionGamma() -> GammaBlackout {
    GammaBlackout(driver: CLIFailingGamma(), lease: GammaLease(url: URL(fileURLWithPath: ProcessInfo.processInfo.environment["CURTAIN_TEST_GAMMA_LEASE"]!)))
}
