import Foundation
import Crypto

/// A shareable event link: `https://sealed.app/e/<eventID>#<key>`.
///
/// The event key lives in the URL fragment, which browsers and URLSession never send to
/// the server. The server stores only `EventCipher` ciphertext indexed by `eventID`, so it
/// can't read event details even if it's compromised.
public struct EventLink: Equatable {
    public static let host = "sealed.app"

    public let eventID: String
    public let key: SymmetricKey

    public init(eventID: String, key: SymmetricKey) {
        self.eventID = eventID
        self.key = key
    }

    /// New random event ID (96 bits) and 256-bit key.
    public static func generate() -> EventLink {
        var idBytes = [UInt8](repeating: 0, count: 12)
        for i in idBytes.indices { idBytes[i] = UInt8.random(in: .min ... .max) }
        return EventLink(eventID: Data(idBytes).base64URLEncodedString(),
                         key: SymmetricKey(size: .bits256))
    }

    public var keyString: String {
        key.withUnsafeBytes { Data($0) }.base64URLEncodedString()
    }

    public var url: URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host = Self.host
        c.path = "/e/\(eventID)"
        c.fragment = keyString
        return c.url!
    }

    /// Parses `https://sealed.app/e/<id>#<key>` (also accepts the `sealed://e/<id>#<key>` scheme).
    public init?(url: URL) {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let fragment = c.fragment,
              let keyData = Data(base64URLEncoded: fragment),
              keyData.count == 32 else { return nil }

        let segments: [String]
        if c.scheme == "sealed" {
            segments = ([c.host ?? ""] + c.path.split(separator: "/").map(String.init)).filter { !$0.isEmpty }
        } else {
            guard c.scheme == "https", c.host == Self.host else { return nil }
            segments = c.path.split(separator: "/").map(String.init)
        }
        guard segments.count == 2, segments[0] == "e", !segments[1].isEmpty else { return nil }

        self.eventID = segments[1]
        self.key = SymmetricKey(data: keyData)
    }

    public static func == (lhs: EventLink, rhs: EventLink) -> Bool {
        lhs.eventID == rhs.eventID && lhs.keyString == rhs.keyString
    }
}
