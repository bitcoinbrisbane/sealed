import Foundation

/// Who can join an event.
public enum EventAccess: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Anyone holding the link (and therefore the key in its fragment) can open and RSVP.
    case anyoneWithLink
    /// Link opens the event, but the guest must send a signed join request the host approves.
    case requestToJoin
    /// No public link: the link is PGP-encrypted to each chosen contact.
    case contactsOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .anyoneWithLink: "Anyone with the link"
        case .requestToJoin: "Request to join"
        case .contactsOnly: "Only contacts I pick"
        }
    }

    public var subtitle: String {
        switch self {
        case .anyoneWithLink: "Opens straight to the event. Best for low-stakes gatherings."
        case .requestToJoin: "Guests sign a request with their key. You approve each one."
        case .contactsOnly: "Encrypted to each contact's PGP key. No public link."
        }
    }
}

/// Event content. Always encrypted client-side before it leaves the device.
public struct EventDetails: Codable, Equatable, Sendable {
    public var title: String
    public var startsAt: Date
    public var location: String?
    /// When true the location is NOT included in the link-readable payload; approved
    /// guests receive it separately, encrypted to their key.
    public var revealLocationAfterApproval: Bool
    public var notes: String
    public var guestLimit: Int?
    public var hostName: String
    public var hostFingerprint: Fingerprint

    public init(title: String, startsAt: Date, location: String? = nil,
                revealLocationAfterApproval: Bool = true, notes: String = "",
                guestLimit: Int? = nil, hostName: String, hostFingerprint: Fingerprint) {
        self.title = title
        self.startsAt = startsAt
        self.location = location
        self.revealLocationAfterApproval = revealLocationAfterApproval
        self.notes = notes
        self.guestLimit = guestLimit
        self.hostName = hostName
        self.hostFingerprint = hostFingerprint
    }

    /// The copy readable by anyone holding the link — strips the location if it is gated.
    public var linkReadable: EventDetails {
        var copy = self
        if revealLocationAfterApproval { copy.location = nil }
        return copy
    }
}

public enum EventRole: String, Codable, Sendable { case host, guest }

public struct Event: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var details: EventDetails
    public var access: EventAccess
    public var role: EventRole
    public var goingCount: Int
    public var pendingRequests: Int

    public init(id: String, details: EventDetails, access: EventAccess, role: EventRole,
                goingCount: Int = 0, pendingRequests: Int = 0) {
        self.id = id
        self.details = details
        self.access = access
        self.role = role
        self.goingCount = goingCount
        self.pendingRequests = pendingRequests
    }
}

/// How much we trust that a contact's key really belongs to them.
public enum TrustLevel: String, Codable, Sendable, Comparable {
    /// Found on a keyserver; nobody has compared fingerprints.
    case keyserverUnverified
    /// User confirmed the fingerprint over a trusted channel (call, Signal, etc.).
    case fingerprintCompared
    /// Mutual QR scan in person.
    case qrVerified

    private var rank: Int {
        switch self {
        case .keyserverUnverified: 0
        case .fingerprintCompared: 1
        case .qrVerified: 2
        }
    }

    public static func < (lhs: TrustLevel, rhs: TrustLevel) -> Bool { lhs.rank < rhs.rank }

    public var isVerified: Bool { self != .keyserverUnverified }
}

public struct Contact: Identifiable, Codable, Equatable, Sendable {
    public var id: Fingerprint { fingerprint }
    public var name: String
    public var email: String?
    public var fingerprint: Fingerprint
    public var publicKeyArmored: String
    public var trust: TrustLevel
    public var addedAt: Date

    public init(name: String, email: String? = nil, fingerprint: Fingerprint,
                publicKeyArmored: String, trust: TrustLevel, addedAt: Date = Date()) {
        self.name = name
        self.email = email
        self.fingerprint = fingerprint
        self.publicKeyArmored = publicKeyArmored
        self.trust = trust
        self.addedAt = addedAt
    }

    public var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

/// A guest's request to join a `.requestToJoin` event. The host verifies `signature`
/// over `signedPayload` with `guestPublicKeyArmored` before showing it.
public struct JoinRequest: Codable, Equatable, Sendable {
    public var eventID: String
    public var guestName: String
    public var guestFingerprint: Fingerprint
    public var guestPublicKeyArmored: String
    public var createdAt: Date
    /// Armored detached signature over `signedPayload`.
    public var signature: String

    public init(eventID: String, guestName: String, guestFingerprint: Fingerprint,
                guestPublicKeyArmored: String, createdAt: Date = Date(), signature: String) {
        self.eventID = eventID
        self.guestName = guestName
        self.guestFingerprint = guestFingerprint
        self.guestPublicKeyArmored = guestPublicKeyArmored
        self.createdAt = createdAt
        self.signature = signature
    }

    /// Canonical bytes the guest signs. Binds the request to one event and one moment
    /// so it can't be replayed against another event.
    public static func signedPayload(eventID: String, guestFingerprint: Fingerprint, createdAt: Date) -> Data {
        let ts = Int(createdAt.timeIntervalSince1970)
        return Data("sealed-join-request:v1:\(eventID):\(guestFingerprint.hex):\(ts)".utf8)
    }

    public var signedPayload: Data {
        Self.signedPayload(eventID: eventID, guestFingerprint: guestFingerprint, createdAt: createdAt)
    }
}
