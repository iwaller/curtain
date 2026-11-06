import Foundation

/// 发布版本号，用于检查更新时比较新旧。
///
/// 按数字逐段比较（0.10.0 比 0.9.0 新），段数不同时缺的段按 0 计（1.2 与 1.2.0 相同）。
/// 发布标签常带前缀 v（如 v0.2.0），解析时去掉。
struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    let components: [Int]

    /// - Parameter string: 版本号或发布标签，如 `0.2.0`、`v0.2.0`。
    /// - Returns: 不是纯数字加点的版本号时（如 `0.2.0-beta`、空串）返回 nil。
    init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var components: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(part), value >= 0 else { return nil }
            components.append(value)
        }
        self.components = components
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
