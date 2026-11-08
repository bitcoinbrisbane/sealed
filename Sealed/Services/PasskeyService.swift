import AuthenticationServices
import UIKit

/// Wraps ASAuthorizationController for passkey registration and sign-in.
///
/// Requires the Associated Domains entitlement `webcredentials:sealed.app` and an
/// apple-app-site-association file served from https://sealed.app/.well-known/.
@MainActor
final class PasskeyService: NSObject {
    static let relyingParty = "sealed.app"

    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: PasskeyService.relyingParty)

    /// Creates a new passkey, saved to iCloud Keychain.
    func register(userName: String, userID: Data, challenge: Data) async throws
        -> ASAuthorizationPlatformPublicKeyCredentialRegistration {
        let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: userName, userID: userID)
        let auth = try await perform([request], preferImmediatelyAvailable: false)
        guard let credential = auth.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            throw ASAuthorizationError(.failed)
        }
        return credential
    }

    /// Signs in with an existing passkey.
    /// - Parameter preferImmediatelyAvailable: true fails fast if this device has no passkey;
    ///   false also offers "use a passkey from a nearby device" (QR / hybrid transport).
    func signIn(challenge: Data, preferImmediatelyAvailable: Bool) async throws
        -> ASAuthorizationPlatformPublicKeyCredentialAssertion {
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        let auth = try await perform([request], preferImmediatelyAvailable: preferImmediatelyAvailable)
        guard let credential = auth.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw ASAuthorizationError(.failed)
        }
        return credential
    }

    private func perform(_ requests: [ASAuthorizationRequest], preferImmediatelyAvailable: Bool) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { cont in
            continuation?.resume(throwing: ASAuthorizationError(.canceled))
            continuation = cont
            let controller = ASAuthorizationController(authorizationRequests: requests)
            controller.delegate = self
            controller.presentationContextProvider = self
            if preferImmediatelyAvailable {
                controller.performRequests(options: .preferImmediatelyAvailableCredentials)
            } else {
                controller.performRequests()
            }
        }
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

extension PasskeyService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated { finish(.success(authorization)) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }
}

extension PasskeyService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
