import XCTest
@testable import SealedCore

final class SealedCoreTests: XCTestCase {
    let fp = Fingerprint("7A3F 9C21 E04B 88D2 51AA  0F6E C93B 2D17 4E80 B615")!

    // MARK: Base64URL

    func testBase64URLRoundTrip() {
        for n in 0..<40 {
            let d = Data((0..<n).map { UInt8(($0 * 37 + 11) % 256) })
            let s = d.base64URLEncodedString()
            XCTAssertFalse(s.contains("=") || s.contains("+") || s.contains("/"))
            XCTAssertEqual(Data(base64URLEncoded: s), d)
        }
    }

    // MARK: Fingerprint

    func testFingerprintParsingAndFormatting() {
        XCTAssertEqual(fp.hex, "7A3F9C21E04B88D251AA0F6EC93B2D174E80B615")
        XCTAssertEqual(fp.grouped, "7A3F 9C21 E04B 88D2 51AA  0F6E C93B 2D17 4E80 B615")
        XCTAssertEqual(fp.short, "7A3F 9C21 … 4E80 B615")
        XCTAssertEqual(fp.keyID, "C93B2D174E80B615")
        XCTAssertEqual(Fingerprint("0x7a3f9c21e04b88d251aa0f6ec93b2d174e80b615"), fp)
        XCTAssertNil(Fingerprint("7A3F"))
        XCTAssertNil(Fingerprint(String(repeating: "Z", count: 40)))
        XCTAssertNotNil(Fingerprint(String(repeating: "A", count: 64)))
    }

    // MARK: EventLink

    func testEventLinkRoundTrip() {
        let link = EventLink.generate()
        let url = link.url
        XCTAssertEqual(url.host, "sealed.app")
        XCTAssertEqual(url.fragment, link.keyString)
        XCTAssertEqual(link.keyString.count, 43)
        XCTAssertEqual(EventLink(url: url), link)
    }

    func testEventLinkCustomScheme() {
        let link = EventLink.generate()
        let url = URL(string: "sealed://e/\(link.eventID)#\(link.keyString)")!
        XCTAssertEqual(EventLink(url: url), link)
    }

    func testEventLinkRejectsBadInput() {
        let link = EventLink.generate()
        XCTAssertNil(EventLink(url: URL(string: "https://sealed.app/e/\(link.eventID)")!), "no key")
        XCTAssertNil(EventLink(url: URL(string: "https://evil.example/e/\(link.eventID)#\(link.keyString)")!))
        XCTAssertNil(EventLink(url: URL(string: "https://sealed.app/x/\(link.eventID)#\(link.keyString)")!))
        XCTAssertNil(EventLink(url: URL(string: "https://sealed.app/e/\(link.eventID)#short")!))
    }

    // MARK: EventCipher

    func details() -> EventDetails {
        EventDetails(title: "Founders' poker night", startsAt: Date(timeIntervalSince1970: 1_795_000_000),
                     location: "12 Example St", revealLocationAfterApproval: true,
                     notes: "Bring a bottle", guestLimit: 8, hostName: "Lucas", hostFingerprint: fp)
    }

    func testCipherRoundTrip() throws {
        let link = EventLink.generate()
        let env = try EventCipher.seal(details(), link: link)
        XCTAssertEqual(env.eventID, link.eventID)
        XCTAssertNil(env.ciphertext.range(of: Data("poker".utf8)), "plaintext must not leak")
        let opened: EventDetails = try EventCipher.open(env, link: link)
        XCTAssertEqual(opened, details())
    }

    func testCipherRejectsWrongKeyAndSwappedEnvelope() throws {
        let a = EventLink.generate(), b = EventLink.generate()
        let env = try EventCipher.seal(details(), link: a)
        XCTAssertThrowsError(try EventCipher.open(env, link: EventLink(eventID: a.eventID, key: b.key), as: EventDetails.self))

        // Server relabels A's ciphertext as event B: rejected.
        var swapped = env
        swapped.eventID = b.eventID
        XCTAssertThrowsError(try EventCipher.open(swapped, link: EventLink(eventID: b.eventID, key: a.key), as: EventDetails.self))
    }

    func testLinkReadableStripsGatedLocation() {
        XCTAssertNil(details().linkReadable.location)
        var open = details()
        open.revealLocationAfterApproval = false
        XCTAssertEqual(open.linkReadable.location, "12 Example St")
    }

    // MARK: ContactCard

    func testContactCardRoundTrip() {
        let card = ContactCard(fingerprint: fp, name: "Lucas: the host 🃏")
        XCTAssertTrue(card.payload.hasPrefix("sealed:1:7A3F"))
        XCTAssertEqual(ContactCard(payload: card.payload), card)
        XCTAssertNil(ContactCard(payload: "sealed:2:\(fp.hex):x"))
        XCTAssertNil(ContactCard(payload: "hello"))
    }

    func testContactCardRejectsMismatchedKey() {
        let card = ContactCard(fingerprint: fp, name: "Lucas")
        let good = PGPPublicKey(armored: "…", fingerprint: fp, userIDs: ["Lucas <l@example.org>"], algorithm: "Ed25519")
        let other = PGPPublicKey(armored: "…", fingerprint: Fingerprint(String(repeating: "B", count: 40))!,
                                 userIDs: [], algorithm: "Ed25519")
        XCTAssertEqual(card.verifiedContact(with: good)?.trust, .qrVerified)
        XCTAssertEqual(card.verifiedContact(with: good)?.email, "l@example.org")
        XCTAssertNil(card.verifiedContact(with: other))
    }

    // MARK: Keyserver

    func testKeyserverQueryParsing() {
        XCTAssertEqual(KeyserverQuery("  Sam@Example.org "), .email("sam@example.org"))
        XCTAssertEqual(KeyserverQuery(fp.grouped), .fingerprint(fp))
        XCTAssertEqual(KeyserverQuery("0xc93b2d174e80b615"), .keyID("C93B2D174E80B615"))
        XCTAssertNil(KeyserverQuery("not a key"))
        XCTAssertEqual(KeyserverQuery.fingerprint(fp).path, "/vks/v1/by-fingerprint/\(fp.hex)")
        XCTAssertEqual(KeyserverQuery.email("a+b@x.org").path, "/vks/v1/by-email/a+b@x.org")
    }

    // MARK: Models

    func testUserIDParsing() {
        let k = PGPPublicKey(armored: "", fingerprint: fp, userIDs: ["Sam R. <sam@example.org>"], algorithm: "Ed25519")
        XCTAssertEqual(k.primaryName, "Sam R.")
        XCTAssertEqual(k.primaryEmail, "sam@example.org")
    }

    func testJoinRequestPayloadBindsEvent() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let a = JoinRequest.signedPayload(eventID: "abc", guestFingerprint: fp, createdAt: t)
        let b = JoinRequest.signedPayload(eventID: "abd", guestFingerprint: fp, createdAt: t)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(String(data: a, encoding: .utf8), "sealed-join-request:v1:abc:\(fp.hex):1800000000")
    }

    func testTrustOrdering() {
        XCTAssertLessThan(TrustLevel.keyserverUnverified, .fingerprintCompared)
        XCTAssertLessThan(TrustLevel.fingerprintCompared, .qrVerified)
        XCTAssertFalse(TrustLevel.keyserverUnverified.isVerified)
    }
}
