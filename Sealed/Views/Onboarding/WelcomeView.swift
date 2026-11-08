import SwiftUI
import AuthenticationServices

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Spacer()

            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "lock")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Color.sAccent)
                    .frame(width: 72, height: 72)
                    .background(Color.sSurface, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sLine))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Sealed")
                        .font(.system(size: 44, weight: .semibold))
                        .kerning(-0.9)
                    Text("Private events. Invites encrypted end to end, shared only with the people you choose.")
                        .font(.system(size: 19))
                        .foregroundStyle(Color.sSecondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    feature("key", "Sign in with a passkey — no password, no email required.")
                    feature("checkmark.shield", "Your PGP key signs every invite, so guests know it came from you.")
                }
                .padding(.top, 8)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    run { try await model.continueWithPasskey() }
                } label: {
                    Label("Continue with passkey", systemImage: "person.badge.key.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Use a passkey from another device") {
                    run { try await model.signInFromAnotherDevice() }
                }
                .buttonStyle(SecondaryButtonStyle())

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.sWarn)
                        .multilineTextAlignment(.center)
                } else {
                    Text("New here? A passkey is created and synced through your iCloud Keychain.")
                        .font(.footnote)
                        .foregroundStyle(Color.sMuted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }
            .disabled(busy)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .foregroundStyle(Color.sText)
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Color.sMuted).frame(width: 20)
                .accessibilityHidden(true)
            Text(text).font(.system(size: 15)).foregroundStyle(Color.sMuted)
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        busy = true
        errorMessage = nil
        Task {
            defer { busy = false }
            do {
                try await action()
            } catch let error as ASAuthorizationError where error.code == .canceled {
                // User dismissed the sheet — or, on a fresh device, there's no local passkey.
                errorMessage = model.hasAccount ? "No passkey on this iPhone? Try another device." : nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
