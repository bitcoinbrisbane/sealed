import Foundation

/// An OpenPGP key fingerprint: 40 hex chars (v4) or 64 hex chars (v6).
public struct Fingerprint: Hashable, Codable, Sendable, CustomStringConvertible {
    /// Uppercase hex, no spaces.
    public let hex: String

    public init?(_ input: String) {
        var cleaned = input.uppercased().filter { !$0.isWhitespace }
        if cleaned.hasPrefix("0X") { cleaned.removeFirst(2) }
        guard cleaned.count == 40 || cleaned.count == 64,
              cleaned.allSatisfy({ $0.isHexDigit }) else { return nil }
        hex = cleaned
    }

    /// Long key ID — the last 16 hex chars (v4 convention).
    public var keyID: String { String(hex.suffix(16)) }

    /// Blocks of four, split into two lines-worth with a double space in the middle:
    /// `7A3F 9C21 E04B 88D2 51AA  0F6E C93B 2D17 4E80 B615`
    public var grouped: String {
        let blocks = stride(from: 0, to: hex.count, by: 4).map { i -> String in
            let start = hex.index(hex.startIndex, offsetBy: i)
            let end = hex.index(start, offsetBy: 4)
            return String(hex[start..<end])
        }
        let half = blocks.count / 2
        return blocks[..<half].joined(separator: " ") + "  " + blocks[half...].joined(separator: " ")
    }

    /// Compact form for list rows: `7A3F 9C21 … 4E80 B615`
    public var short: String {
        let g = grouped.split(separator: " ").map(String.init)
        return "\(g[0]) \(g[1]) … \(g[g.count - 2]) \(g[g.count - 1])"
    }

    public var description: String { grouped }
}
