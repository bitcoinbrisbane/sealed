import SwiftUI
import SealedCore

struct AddContactView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var result: PGPPublicKey?
    @State private var busy = false
    @State private var status: String?
    @State private var showQR = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Method", selection: $showQR) {
                        Text("Keyserver").tag(false)
                        Text("QR in person").tag(true)
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 6) {
                        LabeledField(label: "Email, fingerprint or key ID") {
                            TextField("sam@example.org", text: $query)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit(search)
                        }
                        HStack(spacing: 4) {
                            Text("Server:").foregroundStyle(Color.sMuted)
                            Text(model.keyserver.baseURL.host() ?? "")
                        }
                        .font(.system(size: 13))
                    }

                    Button("Search", action: search)
                        .buttonStyle(SecondaryButtonStyle(height: 46))
                        .disabled(busy || KeyserverQuery(query) == nil)

                    if busy { ProgressView().frame(maxWidth: .infinity) }
                    if let status { Text(status).font(.subheadline).foregroundStyle(Color.sMuted) }

                    if let key = result { resultCard(key) }
                }
                .padding(20)
            }
            .background(Color.sBackground)
            .navigationTitle("Add contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showQR, onDismiss: { dismiss() }) { QRExchangeView() }
        }
    }

    private func resultCard(_ key: PGPPublicKey) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("1 RESULT").sectionLabel()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Avatar(initials: initials(key.primaryName ?? "?"), size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(key.primaryName ?? "Unnamed key").font(.system(size: 17, weight: .semibold))
                        if let email = key.primaryEmail {
                            Text("\(email) · email confirmed by server").font(.system(size: 13)).foregroundStyle(Color.sMuted)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fingerprint").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.sMuted)
                    Text(key.fingerprint.grouped.replacingOccurrences(of: "  ", with: "\n"))
                        .font(.system(size: 14, design: .monospaced))
                        .textSelection(.enabled)
                }
                HStack(spacing: 16) {
                    Text(key.algorithm)
                    if let created = key.createdAt { Text("Created \(created.formatted(.dateTime.month().year()))") }
                    Text(key.expiresAt.map { "Expires \($0.formatted(.dateTime.month().year()))" } ?? "No expiry")
                }
                .font(.system(size: 13)).foregroundStyle(Color.sSecondary)
            }
            .card()

            Label("Anyone can upload a key. Read the last 4 blocks to them over a call before trusting it.",
                  systemImage: "exclamationmark.triangle")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0xE6D3BA))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sWarnBg, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sWarnLine))

            Button("Add as unverified") {
                model.add(Contact(name: key.primaryName ?? key.primaryEmail ?? key.fingerprint.short,
                                  email: key.primaryEmail, fingerprint: key.fingerprint,
                                  publicKeyArmored: key.armored, trust: .keyserverUnverified))
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private func search() {
        guard let q = KeyserverQuery(query) else { return }
        busy = true
        status = nil
        result = nil
        Task {
            defer { busy = false }
            do {
                result = try await model.lookup(q)
                if result == nil {
                    status = "No key found. Email lookups only match addresses the owner has confirmed."
                }
            } catch {
                status = "Lookup failed: \(error.localizedDescription)"
            }
        }
    }
}
