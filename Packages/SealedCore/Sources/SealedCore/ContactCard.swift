import Foundation

/// The payload shown as a QR code for in-person key exchange:
/// `sealed:1:<FINGERPRINT>:<base64url name>`.
///
/// A QR code is too small to carry a whole public key reliably, so it carries the
/// fingerprint. The scanner fetches the full key (keyserver by fingerprint, or the Sealed
/// key directory) and accepts it only if its fingerprint matches what was scanned. Because
/// the fingerprint came from the person standing in front of you, the contact is saved
/// as `.qrVerified` even when the key bytes travelled over the network.
public struct ContactCard: Equatable, Sendable {
    public static let prefix = "sealed:1:"

    public var fingerprint: Fingerprint
    public var name: String

    public init(fingerprint: Fingerprint, name: String) {
        self.fingerprint = fingerprint
        self.name = name
    }

    public var payload: String {
        Self.prefix + fingerprint.hex + ":" + Data(name.utf8).base64URLEncodedString()
    }

    public init?(payload: String) {
        guard payload.hasPrefix(Self.prefix) else { return nil }
        let rest = payload.dropFirst(Self.prefix.count)
        let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let fp = Fingerprint(String(parts[0])),
              let nameData = Data(base64URLEncoded: String(parts[1])),
              let name = String(data: nameData, encoding: .utf8) else { return nil }
        self.fingerprint = fp
        self.name = name
    }

    /// Builds a verified contact from a scanned card and the key fetched for it.
    /// Returns nil if the fetched key's fingerprint doesn't match — treat that as an attack.
    public func verifiedContact(with fetchedKey: PGPPublicKey) -> Contact? {
        guard fetchedKey.fingerprint == fingerprint else { return nil }
        return Contact(name: name, email: fetchedKey.primaryEmail, fingerprint: fingerprint,
                       publicKeyArmored: fetchedKey.armored, trust: .qrVerified)
    }
}
