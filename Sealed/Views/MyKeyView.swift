import SwiftUI
import SealedCore

struct MyKeyView: View {
    @Environment(AppModel.self) private var model
    @State private var showQR = false

    var body: some View {
        NavigationStack {
            List {
                if let key = model.myKey?.publicKey {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(key.primaryName ?? "Me").font(.title3.weight(.semibold))
                            if let email = key.primaryEmail {
                                Text(email).foregroundStyle(Color.sMuted)
                            }
                            Text(key.fingerprint.grouped.replacingOccurrences(of: "  ", with: "\n"))
                                .font(.system(size: 14, design: .monospaced))
                                .textSelection(.enabled)
                            Text(key.algorithm).font(.footnote).foregroundStyle(Color.sMuted)
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.sSurface)

                    Section {
                        Button { showQR = true } label: { Label("Show my QR code", systemImage: "qrcode") }
                        ShareLink(item: key.armored, preview: SharePreview("\(key.primaryName ?? "My") public key")) {
                            Label("Share public key", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            UIPasteboard.general.string = key.fingerprint.grouped
                        } label: { Label("Copy fingerprint", systemImage: "doc.on.doc") }
                    }
                    .listRowBackground(Color.sSurface)
                }

                Section {
                    Button("Sign out", role: .destructive) { model.signOut() }
                } footer: {
                    Text("Your private key stays in this iPhone's Keychain. Signing back in with your passkey unlocks it again.")
                }
                .listRowBackground(Color.sSurface)
            }
            .scrollContentBackground(.hidden)
            .background(Color.sBackground)
            .navigationTitle("My key")
            .sheet(isPresented: $showQR) { QRExchangeView() }
        }
    }
}
