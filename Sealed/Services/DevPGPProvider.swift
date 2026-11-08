import Foundation
import CryptoKit
import SealedCore

enum PGPProviderFactory {
    /// Swap in the real OpenPGP provider here (see README → "PGP library").
    static func make() -> PGPProvider {
        #if DEBUG
        DevPGPProvider()
        #else
        UnimplementedPGPProvider()
        #endif
    }
}

/// Release-build placeholder until a real OpenPGP library is wired in.
struct UnimplementedPGPProvider: PGPProvider {
    func generateKey(name: String, email: String?) throws -> PGPSecretKey { throw PGPError.notImplemented }
    func importSecretKey(armored: String, passphrase: String?) throws -> PGPSecretKey { throw PGPError.notImplemented }
    func readPublicKey(armored: String) throws -> PGPPublicKey { throw PGPError.notImplemented }
    func encrypt(_ data: Data, to recipients: [PGPPublicKey], signedBy signer: PGPSecretKey?) throws -> String { throw PGPError.notImplemented }
    func decrypt(_ armoredMessage: String, with key: PGPSecretKey) throws -> Data { throw PGPError.notImplemented }
    func sign(_ data: Data, with key: PGPSecretKey) throws -> String { throw PGPError.notImplemented }
    func verify(_ data: Data, signature: String, from key: PGPPublicKey) throws -> Bool { throw PGPError.notImplemented }
}

#if DEBUG
/// ⚠️ DEVELOPMENT ONLY — NOT OpenPGP and NOT confidential.
///
/// Lets the UI run end to end in the simulator before a real PGP library is integrated.
/// Signatures are real Ed25519, but "encryption" is plain base64 with a recipient list.
/// Its keys are not interoperable with GnuPG or keyservers.
struct DevPGPProvider: PGPProvider {
    private struct KeyBlob: Codable {
        var name: String
        var email: String?
        var publicKey: Data
        var privateKey: Data?
        var created: Date
    }

    private struct MessageBlob: Codable {
        var recipients: [String]
        var plaintext: Data
        var signer: String?
    }

    private static let pubHeader = "SEALED DEV PUBLIC KEY"
    private static let secHeader = "SEALED DEV PRIVATE KEY"
    private static let msgHeader = "SEALED DEV MESSAGE (NOT ENCRYPTED)"
    private static let sigHeader = "SEALED DEV SIGNATURE"

    private func armor<T: Encodable>(_ value: T, _ header: String) throws -> String {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let body = try e.encode(value).base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN \(header)-----\n\(body)\n-----END \(header)-----"
    }

    private func dearmor<T: Decodable>(_ s: String, _ header: String, as: T.Type) throws -> T {
        guard s.contains("-----BEGIN \(header)-----") else { throw PGPError.invalidKey("Not a \(header.lowercased())") }
        let body = s.components(separatedBy: "\n").filter { !$0.hasPrefix("-----") }.joined()
        guard let data = Data(base64Encoded: body, options: .ignoreUnknownCharacters) else { throw PGPError.invalidKey("Corrupt armor") }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try d.decode(T.self, from: data)
    }

    private func fingerprint(_ pub: Data) -> Fingerprint {
        let digest = SHA256.hash(data: pub).prefix(20)
        return Fingerprint(digest.map { String(format: "%02X", $0) }.joined())!
    }

    private func publicKey(from blob: KeyBlob) throws -> PGPPublicKey {
        var pub = blob; pub.privateKey = nil
        let uid = blob.email.map { "\(blob.name) <\($0)>" } ?? blob.name
        return PGPPublicKey(armored: try armor(pub, Self.pubHeader), fingerprint: fingerprint(blob.publicKey),
                            userIDs: [uid], algorithm: "Ed25519 (dev)", createdAt: blob.created)
    }

    func generateKey(name: String, email: String?) throws -> PGPSecretKey {
        let key = Curve25519.Signing.PrivateKey()
        let blob = KeyBlob(name: name, email: email, publicKey: key.publicKey.rawRepresentation,
                           privateKey: key.rawRepresentation, created: .now)
        return PGPSecretKey(armoredSecretKey: try armor(blob, Self.secHeader), publicKey: try publicKey(from: blob))
    }

    func importSecretKey(armored: String, passphrase: String?) throws -> PGPSecretKey {
        if armored.contains("BEGIN PGP PRIVATE KEY BLOCK") {
            throw PGPError.invalidKey("Importing real OpenPGP keys needs the OpenPGP provider (see README).")
        }
        let blob = try dearmor(armored, Self.secHeader, as: KeyBlob.self)
        return PGPSecretKey(armoredSecretKey: armored, publicKey: try publicKey(from: blob))
    }

    func readPublicKey(armored: String) throws -> PGPPublicKey {
        try publicKey(from: try dearmor(armored, Self.pubHeader, as: KeyBlob.self))
    }

    func encrypt(_ data: Data, to recipients: [PGPPublicKey], signedBy signer: PGPSecretKey?) throws -> String {
        try armor(MessageBlob(recipients: recipients.map(\.fingerprint.hex), plaintext: data,
                              signer: signer?.publicKey.fingerprint.hex), Self.msgHeader)
    }

    func decrypt(_ armoredMessage: String, with key: PGPSecretKey) throws -> Data {
        let msg = try dearmor(armoredMessage, Self.msgHeader, as: MessageBlob.self)
        guard msg.recipients.contains(key.publicKey.fingerprint.hex) else { throw PGPError.decryptionFailed }
        return msg.plaintext
    }

    func sign(_ data: Data, with key: PGPSecretKey) throws -> String {
        let blob = try dearmor(key.armoredSecretKey, Self.secHeader, as: KeyBlob.self)
        guard let raw = blob.privateKey else { throw PGPError.invalidKey("No private key") }
        let sig = try Curve25519.Signing.PrivateKey(rawRepresentation: raw).signature(for: data)
        return "-----BEGIN \(Self.sigHeader)-----\n\(sig.base64EncodedString())\n-----END \(Self.sigHeader)-----"
    }

    func verify(_ data: Data, signature: String, from key: PGPPublicKey) throws -> Bool {
        let blob = try dearmor(key.armored, Self.pubHeader, as: KeyBlob.self)
        let body = signature.components(separatedBy: "\n").filter { !$0.hasPrefix("-----") }.joined()
        guard let sig = Data(base64Encoded: body, options: .ignoreUnknownCharacters) else { return false }
        return try Curve25519.Signing.PublicKey(rawRepresentation: blob.publicKey).isValidSignature(sig, for: data)
    }
}
#endif
