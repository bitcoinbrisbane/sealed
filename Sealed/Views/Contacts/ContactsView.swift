import SwiftUI
import SealedCore

struct ContactsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var adding = false
    @State private var exchanging = false

    private var filtered: [Contact] {
        guard !search.isEmpty else { return model.contacts }
        let q = search.lowercased()
        let hex = q.uppercased().filter { !$0.isWhitespace }
        return model.contacts.filter {
            $0.name.lowercased().contains(q) || ($0.email?.contains(q) ?? false) || $0.fingerprint.hex.contains(hex)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                let verified = filtered.filter { $0.trust.isVerified }
                let unverified = filtered.filter { !$0.trust.isVerified }

                if model.contacts.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No contacts yet").font(.headline)
                            Text("Scan someone's QR code in person, or look them up on a keyserver by email or fingerprint.")
                                .font(.subheadline).foregroundStyle(Color.sMuted)
                        }
                        .padding(.vertical, 6)
                    }
                }

                if !verified.isEmpty {
                    Section("Verified") {
                        ForEach(verified) { row($0) }
                    }
                }
                if !unverified.isEmpty {
                    Section {
                        ForEach(unverified) { row($0) }
                    } header: {
                        Text("From keyserver")
                    } footer: {
                        Text("Compare fingerprints in person or over a call, then swipe to mark a contact as verified.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.sBackground)
            .searchable(text: $search, prompt: "Name, email or fingerprint")
            .navigationTitle("Contacts")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { exchanging = true } label: { Image(systemName: "qrcode") }
                        .accessibilityLabel("Exchange keys by QR")
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add contact")
                }
            }
            .sheet(isPresented: $adding) { AddContactView() }
            .sheet(isPresented: $exchanging) { QRExchangeView() }
        }
    }

    private func row(_ c: Contact) -> some View {
        HStack(spacing: 12) {
            Avatar(initials: c.initials)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.name).font(.system(size: 16, weight: .medium))
                if c.trust.isVerified {
                    Text(c.fingerprint.short).font(.sMonoSmall).foregroundStyle(Color.sMuted)
                } else {
                    Text(c.email ?? c.fingerprint.short).font(.system(size: 12)).foregroundStyle(Color.sMuted)
                }
            }
            Spacer()
            switch c.trust {
            case .qrVerified:
                Label("QR", systemImage: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.sAccent)
            case .fingerprintCompared:
                Label("Checked", systemImage: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.sAccent)
            case .keyserverUnverified:
                Text("Unverified").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.sWarn)
            }
        }
        .listRowBackground(Color.sSurface)
        .swipeActions {
            Button(role: .destructive) { model.remove(c) } label: { Label("Remove", systemImage: "trash") }
            if !c.trust.isVerified {
                Button { model.markFingerprintCompared(c) } label: { Label("Verified", systemImage: "checkmark.seal") }
                    .tint(.green)
            }
        }
        .contextMenu {
            Button { UIPasteboard.general.string = c.fingerprint.grouped } label: {
                Label("Copy fingerprint", systemImage: "doc.on.doc")
            }
        }
    }
}
