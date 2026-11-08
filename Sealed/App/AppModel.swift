import Foundation
import Observation
import AuthenticationServices
import SealedCore

@MainActor
@Observable
final class AppModel {
    enum Phase { case signedOut, needsKey, ready }

    var phase: Phase = .signedOut
    var myKey: PGPSecretKey?
    var contacts: [Contact] = [] { didSet { save() } }
    var events: [Event] = [] { didSet { save() } }
    /// Event links the user has opened (guest side), keyed by event ID.
    var guestLinks: [String: String] = [:] { didSet { save() } }
    /// Set when the app is opened from an event link; drives the guest sheet.
    var openedLink: EventLink?

    let pgp: PGPProvider
    let api: SealedAPI
    let keyserver = KeyserverClient()
    let passkeys = PasskeyService()
    private let keychain = KeychainStore()
    private let defaults = UserDefaults.standard

    private static let secretKeyAccount = "primary"
    private static let hasAccountKey = "hasPasskeyAccount"

    init(pgp: PGPProvider = PGPProviderFactory.make(), api: SealedAPI = InMemorySealedAPI()) {
        self.pgp = pgp
        self.api = api
        load()
    }

    var hasAccount: Bool { defaults.bool(forKey: Self.hasAccountKey) }
    var myName: String { myKey?.publicKey.primaryName ?? "Me" }

    // MARK: Passkeys

    /// First launch creates a passkey; later launches sign in with it.
    func continueWithPasskey() async throws {
        if hasAccount {
            try await signIn(preferImmediatelyAvailable: true)
        } else {
            let (challenge, userID) = try await api.registrationChallenge(displayName: "Sealed")
            let cred = try await passkeys.register(userName: "Sealed account", userID: userID, challenge: challenge)
            try await api.finishRegistration(credentialID: cred.credentialID,
                                             attestationObject: cred.rawAttestationObject ?? Data(),
                                             clientDataJSON: cred.rawClientDataJSON)
            defaults.set(true, forKey: Self.hasAccountKey)
            afterSignIn()
        }
    }

    /// Hybrid sign-in: shows the QR to use a passkey on another phone or a security key.
    func signInFromAnotherDevice() async throws {
        try await signIn(preferImmediatelyAvailable: false)
    }

    private func signIn(preferImmediatelyAvailable: Bool) async throws {
        let challenge = try await api.assertionChallenge()
        let cred = try await passkeys.signIn(challenge: challenge, preferImmediatelyAvailable: preferImmediatelyAvailable)
        try await api.finishAssertion(credentialID: cred.credentialID, userID: cred.userID,
                                      signature: cred.signature, authenticatorData: cred.rawAuthenticatorData,
                                      clientDataJSON: cred.rawClientDataJSON)
        defaults.set(true, forKey: Self.hasAccountKey)
        afterSignIn()
    }

    private func afterSignIn() {
        if myKey == nil, let armored = try? keychain.load(account: Self.secretKeyAccount),
           let key = try? pgp.importSecretKey(armored: armored, passphrase: nil) {
            myKey = key
        }
        phase = myKey == nil ? .needsKey : .ready
    }

    func signOut() {
        myKey = nil
        phase = .signedOut
    }

    // MARK: PGP identity

    struct PublishResult { var emailVerificationSent: Bool }

    func generateKey(name: String, email: String?, publishToKeyserver: Bool) async throws -> PublishResult {
        let email = email?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        let key = try pgp.generateKey(name: name, email: email)
        try adopt(key)

        // Publishing is best-effort: the key is already saved, so a keyserver hiccup
        // shouldn't strand the user on the setup screen. They can publish later from My key.
        var sent = false
        if publishToKeyserver, let email {
            do {
                let upload = try await keyserver.upload(armoredPublicKey: key.publicKey.armored)
                try await keyserver.requestVerification(token: upload.token, addresses: [email])
                sent = true
            } catch {
                print("Keyserver publish failed: \(error)")
            }
        }
        return PublishResult(emailVerificationSent: sent)
    }

    func importKey(armored: String, passphrase: String?) throws {
        try adopt(try pgp.importSecretKey(armored: armored, passphrase: passphrase?.nilIfEmpty))
        phase = .ready
    }

    /// Stores the key. The caller moves `phase` to `.ready` when onboarding UI is finished.
    private func adopt(_ key: PGPSecretKey) throws {
        try keychain.save(key.armoredSecretKey, account: Self.secretKeyAccount)
        myKey = key
        Task { try? await api.publishPublicKey(key.publicKey.armored, fingerprint: key.publicKey.fingerprint) }
    }

    // MARK: Events (host)

    /// Encrypts, signs and uploads an event. Returns the link to share.
    @discardableResult
    func publish(_ details: EventDetails, link: EventLink, access: EventAccess,
                 inviting invitees: [Contact]) async throws -> EventLink {
        guard let me = myKey else { throw PGPError.invalidKey("No key") }

        var envelope = try EventCipher.seal(details.linkReadable, link: link)
        envelope.hostSignature = try pgp.sign(envelope.ciphertext, with: me)
        try await api.putEvent(envelope, access: access)

        if access == .contactsOnly, !invitees.isEmpty {
            let invite = try ContactInvite.make(link: link, for: invitees, host: me, pgp: pgp)
            for contact in invitees {
                try await api.deliverInvite(armored: invite, to: contact.fingerprint)
            }
        }

        events.insert(Event(id: link.eventID, details: details, access: access, role: .host), at: 0)
        return link
    }

    // MARK: Events (guest)

    func handle(url: URL) {
        if let link = EventLink(url: url) { openedLink = link }
    }

    struct OpenedEvent {
        var details: EventDetails
        /// Host's signature verified against a key we already trust.
        var hostVerified: Bool
        var hostContact: Contact?
    }

    func open(_ link: EventLink) async throws -> OpenedEvent? {
        guard let envelope = try await api.getEvent(id: link.eventID) else { return nil }
        let details: EventDetails = try EventCipher.open(envelope, link: link)
        guardLinkSaved(link)

        let contact = contacts.first { $0.fingerprint == details.hostFingerprint }
        var verified = false
        if let contact, let sig = envelope.hostSignature,
           let key = try? pgp.readPublicKey(armored: contact.publicKeyArmored) {
            verified = (try? pgp.verify(envelope.ciphertext, signature: sig, from: key)) ?? false
        }
        return OpenedEvent(details: details, hostVerified: verified, hostContact: contact)
    }

    private func guardLinkSaved(_ link: EventLink) {
        if guestLinks[link.eventID] == nil { guestLinks[link.eventID] = link.url.absoluteString }
    }

    func requestToJoin(_ link: EventLink) async throws {
        guard let me = myKey else { throw PGPError.invalidKey("No key") }
        let now = Date.now
        let payload = JoinRequest.signedPayload(eventID: link.eventID, guestFingerprint: me.publicKey.fingerprint, createdAt: now)
        let request = JoinRequest(eventID: link.eventID, guestName: myName,
                                  guestFingerprint: me.publicKey.fingerprint,
                                  guestPublicKeyArmored: me.publicKey.armored,
                                  createdAt: now, signature: try pgp.sign(payload, with: me))
        try await api.sendJoinRequest(request)
    }

    // MARK: Contacts

    func lookup(_ query: KeyserverQuery) async throws -> PGPPublicKey? {
        guard let armored = try await keyserver.lookup(query) else { return nil }
        return try pgp.readPublicKey(armored: armored)
    }

    func add(_ contact: Contact) {
        if let i = contacts.firstIndex(where: { $0.fingerprint == contact.fingerprint }) {
            // Never downgrade trust when re-adding.
            if contact.trust > contacts[i].trust { contacts[i] = contact }
        } else {
            contacts.append(contact)
        }
    }

    func markFingerprintCompared(_ contact: Contact) {
        guard let i = contacts.firstIndex(of: contact), contacts[i].trust < .fingerprintCompared else { return }
        contacts[i].trust = .fingerprintCompared
    }

    func remove(_ contact: Contact) {
        contacts.removeAll { $0.fingerprint == contact.fingerprint }
    }

    /// Resolves a scanned QR card: Sealed directory first, then the keyserver.
    func resolve(_ card: ContactCard) async throws -> Contact? {
        var armored = try await api.publicKey(for: card.fingerprint)
        if armored == nil { armored = try await keyserver.lookup(.fingerprint(card.fingerprint)) }
        guard let armored else { return nil }
        return card.verifiedContact(with: try pgp.readPublicKey(armored: armored))
    }

    var myContactCard: ContactCard? {
        myKey.map { ContactCard(fingerprint: $0.publicKey.fingerprint, name: myName) }
    }

    // MARK: Persistence (contacts, events — public data; secrets stay in the Keychain)

    private struct Snapshot: Codable {
        var contacts: [Contact]
        var events: [Event]
        var guestLinks: [String: String]
    }

    private var storeURL: URL {
        URL.applicationSupportDirectory.appending(path: "sealed.json")
    }

    @ObservationIgnored private var loading = false

    private func load() {
        loading = true
        defer { loading = false }
        guard let data = try? Data(contentsOf: storeURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        contacts = snap.contacts
        events = snap.events
        guestLinks = snap.guestLinks
    }

    private func save() {
        guard !loading else { return }
        let snap = Snapshot(contacts: contacts, events: events, guestLinks: guestLinks)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Guest links contain event keys, so protect the file at rest.
        try? data.write(to: storeURL, options: [.atomic, .completeFileProtection])
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
