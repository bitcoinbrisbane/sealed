import Foundation
import SealedCore

/// The Sealed backend. It only ever sees passkey assertions, public keys, ciphertext
/// envelopes, PGP-encrypted invites and signed join requests — never event plaintext.
protocol SealedAPI: Sendable {
    // Passkeys (WebAuthn)
    func registrationChallenge(displayName: String) async throws -> (challenge: Data, userID: Data)
    func finishRegistration(credentialID: Data, attestationObject: Data, clientDataJSON: Data) async throws
    func assertionChallenge() async throws -> Data
    func finishAssertion(credentialID: Data, userID: Data, signature: Data,
                         authenticatorData: Data, clientDataJSON: Data) async throws

    // Key directory — lets QR scans resolve a fingerprint to a full key without a keyserver.
    func publishPublicKey(_ armored: String, fingerprint: Fingerprint) async throws
    func publicKey(for fingerprint: Fingerprint) async throws -> String?

    // Events
    func putEvent(_ envelope: SealedEnvelope, access: EventAccess) async throws
    func getEvent(id: String) async throws -> SealedEnvelope?

    // Invites & requests
    func deliverInvite(armored: String, to recipient: Fingerprint) async throws
    func sendJoinRequest(_ request: JoinRequest) async throws
    func joinRequests(eventID: String) async throws -> [JoinRequest]
}

enum SealedAPIError: Error {
    case unknownCredential
}

/// In-process stand-in so the app runs before the server exists.
/// Replace with an HTTP implementation against your backend.
actor InMemorySealedAPI: SealedAPI {
    private var keys: [Fingerprint: String] = [:]
    private var events: [String: SealedEnvelope] = [:]
    private var requests: [String: [JoinRequest]] = [:]
    private var invites: [Fingerprint: [String]] = [:]
    private var credentials: Set<Data> = []

    private func random(_ n: Int) -> Data {
        Data((0..<n).map { _ in UInt8.random(in: .min ... .max) })
    }

    func registrationChallenge(displayName: String) async throws -> (challenge: Data, userID: Data) {
        (random(32), random(16))
    }

    func finishRegistration(credentialID: Data, attestationObject: Data, clientDataJSON: Data) async throws {
        // Real server: verify attestation + challenge, store the credential's public key.
        credentials.insert(credentialID)
    }

    func assertionChallenge() async throws -> Data { random(32) }

    func finishAssertion(credentialID: Data, userID: Data, signature: Data,
                         authenticatorData: Data, clientDataJSON: Data) async throws {
        // Real server: verify the signature with the stored credential public key.
        // The stub accepts any credential so a synced passkey from a previous install works.
    }

    func publishPublicKey(_ armored: String, fingerprint: Fingerprint) async throws {
        keys[fingerprint] = armored
    }

    func publicKey(for fingerprint: Fingerprint) async throws -> String? { keys[fingerprint] }

    func putEvent(_ envelope: SealedEnvelope, access: EventAccess) async throws {
        events[envelope.eventID] = envelope
    }

    func getEvent(id: String) async throws -> SealedEnvelope? { events[id] }

    func deliverInvite(armored: String, to recipient: Fingerprint) async throws {
        invites[recipient, default: []].append(armored)
    }

    func sendJoinRequest(_ request: JoinRequest) async throws {
        requests[request.eventID, default: []].append(request)
    }

    func joinRequests(eventID: String) async throws -> [JoinRequest] { requests[eventID] ?? [] }
}
