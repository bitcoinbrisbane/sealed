import Foundation
import Crypto

/// What the server stores for an event. Opaque without the link key.
public struct SealedEnvelope: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var eventID: String
    /// ChaCha20-Poly1305 combined box (nonce ‖ ciphertext ‖ tag).
    public var ciphertext: Data
    /// Host's armored detached PGP signature over `ciphertext`, so guests can check the
    /// event really came from the host whose fingerprint is inside.
    public var hostSignature: String?

    public init(version: Int = SealedEnvelope.currentVersion, eventID: String,
                ciphertext: Data, hostSignature: String? = nil) {
        self.version = version
        self.eventID = eventID
        self.ciphertext = ciphertext
        self.hostSignature = hostSignature
    }
}

public enum EventCipherError: Error, Equatable {
    case unsupportedVersion(Int)
    case eventIDMismatch
}

/// Symmetric encryption of event payloads with the link key.
public enum EventCipher {
    private static func aad(_ eventID: String, version: Int) -> Data {
        // Binding the event ID stops a server swapping one event's ciphertext for another's.
        Data("sealed-event:v\(version):\(eventID)".utf8)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .sortedKeys
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func seal<T: Encodable>(_ value: T, link: EventLink) throws -> SealedEnvelope {
        let plaintext = try encoder.encode(value)
        let box = try ChaChaPoly.seal(plaintext, using: link.key,
                                      authenticating: aad(link.eventID, version: SealedEnvelope.currentVersion))
        return SealedEnvelope(eventID: link.eventID, ciphertext: box.combined)
    }

    public static func open<T: Decodable>(_ envelope: SealedEnvelope, link: EventLink, as type: T.Type = T.self) throws -> T {
        guard envelope.version == SealedEnvelope.currentVersion else {
            throw EventCipherError.unsupportedVersion(envelope.version)
        }
        guard envelope.eventID == link.eventID else { throw EventCipherError.eventIDMismatch }
        let box = try ChaChaPoly.SealedBox(combined: envelope.ciphertext)
        let plaintext = try ChaChaPoly.open(box, using: link.key,
                                            authenticating: aad(link.eventID, version: envelope.version))
        return try decoder.decode(T.self, from: plaintext)
    }
}
