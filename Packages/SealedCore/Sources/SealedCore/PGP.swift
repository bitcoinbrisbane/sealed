import Foundation

public struct PGPPublicKey: Equatable, Sendable {
    public var armored: String
    public var fingerprint: Fingerprint
    /// e.g. `["Sam R. <sam@example.org>"]`
    public var userIDs: [String]
    /// e.g. `"Ed25519"`
    public var algorithm: String
    public var createdAt: Date?
    public var expiresAt: Date?

    public init(armored: String, fingerprint: Fingerprint, userIDs: [String],
                algorithm: String, createdAt: Date? = nil, expiresAt: Date? = nil) {
        self.armored = armored
        self.fingerprint = fingerprint
        self.userIDs = userIDs
        self.algorithm = algorithm
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    /// Name part of the first user ID: `"Sam R. <sam@x>"` → `"Sam R."`.
    public var primaryName: String? {
        guard let uid = userIDs.first else { return nil }
        if let lt = uid.firstIndex(of: "<") {
            let name = uid[..<lt].trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
        return uid.contains("@") ? nil : uid
    }

    /// Email part of the first user ID that has one.
    public var primaryEmail: String? {
        for uid in userIDs {
            if let lt = uid.firstIndex(of: "<"), let gt = uid.lastIndex(of: ">"), lt < gt {
                return String(uid[uid.index(after: lt)..<gt])
            }
            if uid.contains("@") && !uid.contains(" ") { return uid }
        }
        return nil
    }
}

/// A user's own key pair. `armoredSecretKey` must only ever live in the Keychain.
public struct PGPSecretKey: Sendable {
    public var armoredSecretKey: String
    public var publicKey: PGPPublicKey

    public init(armoredSecretKey: String, publicKey: PGPPublicKey) {
        self.armoredSecretKey = armoredSecretKey
        self.publicKey = publicKey
    }
}

public enum PGPError: Error, Equatable {
    case notImplemented
    case invalidKey(String)
    case passphraseRequired
    case decryptionFailed
    case badSignature
}

/// The OpenPGP operations Sealed needs. The app talks only to this protocol so the
/// underlying library (GopenPGP, Sequoia, …) can be swapped without touching UI code.
public protocol PGPProvider: Sendable {
    /// New Curve25519 key (Ed25519 signing + X25519 encryption subkey).
    func generateKey(name: String, email: String?) throws -> PGPSecretKey
    func importSecretKey(armored: String, passphrase: String?) throws -> PGPSecretKey
    func readPublicKey(armored: String) throws -> PGPPublicKey

    /// Armored PGP message encrypted to all recipients, optionally signed.
    func encrypt(_ data: Data, to recipients: [PGPPublicKey], signedBy signer: PGPSecretKey?) throws -> String
    func decrypt(_ armoredMessage: String, with key: PGPSecretKey) throws -> Data

    /// Armored detached signature.
    func sign(_ data: Data, with key: PGPSecretKey) throws -> String
    func verify(_ data: Data, signature: String, from key: PGPPublicKey) throws -> Bool
}

/// Contacts-only invites: the event link (including its fragment key) is PGP-encrypted to
/// each chosen contact and signed by the host. Delivered via the Sealed inbox or any side channel.
public enum ContactInvite {
    public static func make(link: EventLink, for contacts: [Contact], host: PGPSecretKey,
                            pgp: PGPProvider) throws -> String {
        let recipients = try contacts.map { try pgp.readPublicKey(armored: $0.publicKeyArmored) }
        // Encrypting to the host too lets them read their own sent invites on another device.
        return try pgp.encrypt(Data(link.url.absoluteString.utf8),
                               to: recipients + [host.publicKey], signedBy: host)
    }

    public static func open(_ armored: String, with key: PGPSecretKey, pgp: PGPProvider) throws -> EventLink {
        let data = try pgp.decrypt(armored, with: key)
        guard let s = String(data: data, encoding: .utf8), let url = URL(string: s),
              let link = EventLink(url: url) else { throw PGPError.decryptionFailed }
        return link
    }
}
