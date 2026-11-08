import SwiftUI
import UniformTypeIdentifiers

struct KeySetupView: View {
    @Environment(AppModel.self) private var model

    enum Mode { case generate, importKey }

    @State private var mode: Mode = .generate
    @State private var name = ""
    @State private var email = ""
    @State private var publish = true
    @State private var armored = ""
    @State private var passphrase = ""
    @State private var showFileImporter = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var verificationSent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("STEP 2 OF 2").sectionLabel()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your PGP identity").font(.system(size: 30, weight: .semibold))
                    Text("Used to sign your invites and decrypt the ones sent to you. The private key never leaves this iPhone.")
                        .font(.system(size: 15)).foregroundStyle(Color.sMuted)
                }

                VStack(spacing: 10) {
                    option(.generate, symbol: "sparkles", title: "Generate a new key",
                           subtitle: "Ed25519 / Curve25519. Recommended if you're new to PGP.")
                    option(.importKey, symbol: "square.and.arrow.down", title: "Import an existing key",
                           subtitle: "Paste an armored key, open a .asc file, or read from a hardware key.")
                }

                if mode == .generate { generateForm } else { importForm }

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(Color.sWarn)
                }

                Button(mode == .generate ? "Create my key" : "Import key", action: submit)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy || !canSubmit)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .foregroundStyle(Color.sText)
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [UTType(filenameExtension: "asc") ?? .plainText, .plainText]) { result in
            guard let url = try? result.get() else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            armored = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        .alert("Check your email", isPresented: $verificationSent) {
            Button("OK") { model.phase = .ready }
        } message: {
            Text("keys.openpgp.org sent a confirmation link to \(email). Once you click it, people can find your key by email.")
        }
    }

    private var canSubmit: Bool {
        mode == .generate ? !name.trimmingCharacters(in: .whitespaces).isEmpty : !armored.isEmpty
    }

    private func option(_ m: Mode, symbol: String, title: String, subtitle: String) -> some View {
        Button { withAnimation(.snappy) { mode = m } } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol).foregroundStyle(Color.sAccent).frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 16, weight: .semibold))
                    Text(subtitle).font(.system(size: 14)).foregroundStyle(Color.sMuted)
                        .multilineTextAlignment(.leading)
                }
            }
            .card(selected: mode == m)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == m ? .isSelected : [])
    }

    private var generateForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledField(label: "Display name") {
                TextField("Your name", text: $name).textContentType(.name)
            }
            LabeledField(label: "Email (optional)") {
                TextField("So others can find you on a keyserver", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }
            Toggle(isOn: $publish) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Publish to keys.openpgp.org").font(.system(size: 15, weight: .medium))
                    Text("Searchable by email once verified").font(.system(size: 13)).foregroundStyle(Color.sMuted)
                }
            }
            .card(padding: 14)
            .disabled(email.isEmpty)
        }
    }

    private var importForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Armored private key").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sMuted)
            TextEditor(text: $armored)
                .font(.sMonoSmall)
                .scrollContentBackground(.hidden)
                .frame(height: 150)
                .padding(8)
                .background(Color.sSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sLine))
                .accessibilityLabel("Armored private key")
            SecureField("Passphrase (if the key has one)", text: $passphrase).fieldStyle()
            HStack(spacing: 10) {
                Button("Open .asc file") { showFileImporter = true }
                    .buttonStyle(SecondaryButtonStyle(height: 44))
                Button("YubiKey (NFC)") {}
                    .buttonStyle(SecondaryButtonStyle(height: 44))
                    .disabled(true) // TODO: OpenPGP card over NFC
            }
        }
    }

    private func submit() {
        busy = true
        errorMessage = nil
        Task {
            defer { busy = false }
            do {
                if mode == .generate {
                    let result = try await model.generateKey(name: name.trimmingCharacters(in: .whitespaces),
                                                             email: email, publishToKeyserver: publish)
                    if result.emailVerificationSent {
                        verificationSent = true // alert's OK moves on
                    } else {
                        model.phase = .ready
                    }
                } else {
                    try model.importKey(armored: armored, passphrase: passphrase)
                }
            } catch {
                errorMessage = "\(error)"
            }
        }
    }
}
