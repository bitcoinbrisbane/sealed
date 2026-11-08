import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What the user typed into "Email, fingerprint or key ID".
public enum KeyserverQuery: Equatable, Sendable {
    case email(String)
    case fingerprint(Fingerprint)
    case keyID(String)

    public init?(_ raw: String) {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.contains("@") {
            guard input.split(separator: "@").count == 2 else { return nil }
            self = .email(input.lowercased())
        } else if let fp = Fingerprint(input) {
            self = .fingerprint(fp)
        } else {
            var hex = input.uppercased().filter { !$0.isWhitespace }
            if hex.hasPrefix("0X") { hex.removeFirst(2) }
            guard hex.count == 16, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
            self = .keyID(hex)
        }
    }

    var path: String {
        switch self {
        case .email(let e):
            let encoded = e.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? e
            return "/vks/v1/by-email/\(encoded)"
        case .fingerprint(let fp): return "/vks/v1/by-fingerprint/\(fp.hex)"
        case .keyID(let id): return "/vks/v1/by-keyid/\(id)"
        }
    }
}

public enum KeyserverError: Error, Equatable {
    case http(Int)
    case badResponse
}

/// Client for the Verifying Key Server API used by keys.openpgp.org.
/// Lookups by email only return keys whose owner has confirmed that address.
public struct KeyserverClient {
    public var baseURL: URL
    public var session: URLSession

    public init(baseURL: URL = URL(string: "https://keys.openpgp.org")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Armored public key, or nil if nothing matches.
    public func lookup(_ query: KeyserverQuery) async throws -> String? {
        let url = URL(string: query.path, relativeTo: baseURL)!
        let (data, response) = try await send(URLRequest(url: url))
        guard let http = response as? HTTPURLResponse else { throw KeyserverError.badResponse }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw KeyserverError.http(http.statusCode) }
        return String(data: data, encoding: .utf8)
    }

    public struct UploadResult: Decodable, Sendable {
        public var token: String
        public var keyFingerprint: String
        /// Email → "unpublished" | "pending" | "published" | "revoked"
        public var status: [String: String]

        enum CodingKeys: String, CodingKey {
            case token
            case keyFingerprint = "key_fpr"
            case status
        }
    }

    public func upload(armoredPublicKey: String) async throws -> UploadResult {
        let body = try JSONEncoder().encode(["keytext": armoredPublicKey])
        let data = try await post("/vks/v1/upload", body: body)
        return try JSONDecoder().decode(UploadResult.self, from: data)
    }

    /// Asks the server to email a confirmation link to each address, which makes the key
    /// findable by that email once clicked.
    public func requestVerification(token: String, addresses: [String]) async throws {
        struct Body: Encodable { var token: String; var addresses: [String] }
        let body = try JSONEncoder().encode(Body(token: token, addresses: addresses))
        _ = try await post("/vks/v1/request-verify", body: body)
    }

    private func post(_ path: String, body: Data) async throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw KeyserverError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw KeyserverError.http(http.statusCode) }
        return data
    }

    /// Continuation-based so it also builds on Linux Foundation versions without async URLSession.
    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            session.dataTask(with: request) { data, response, error in
                if let error { cont.resume(throwing: error); return }
                guard let response else { cont.resume(throwing: KeyserverError.badResponse); return }
                cont.resume(returning: (data ?? Data(), response))
            }.resume()
        }
    }
}
