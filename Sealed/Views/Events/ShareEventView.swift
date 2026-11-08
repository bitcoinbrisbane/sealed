import SwiftUI
import SealedCore

struct ShareEventView: View {
    @Environment(AppModel.self) private var model

    let details: EventDetails
    var onFinish: () -> Void

    /// Generated once per draft; the key never leaves the device except inside the link.
    @State private var link = EventLink.generate()
    @State private var access: EventAccess = .requestToJoin
    @State private var selected: Set<Fingerprint> = []
    @State private var published = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var showQR = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 8) {
                    ForEach(EventAccess.allCases) { option in
                        Button { withAnimation(.snappy) { access = option } } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .strokeBorder(access == option ? Color.sAccent : Color(hex: 0x4A505B),
                                                  lineWidth: access == option ? 6 : 2)
                                    .frame(width: 20, height: 20)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.title).font(.system(size: 16, weight: .semibold))
                                    Text(option.subtitle).font(.system(size: 13)).foregroundStyle(Color.sMuted)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .card(selected: access == option, padding: 14)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(access == option ? .isSelected : [])
                    }
                }
                .disabled(published)

                if access == .contactsOnly { contactPicker } else { linkCard }

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(Color.sWarn)
                }

                Button(action: primaryAction) {
                    if busy { ProgressView().tint(Color.sBackground) } else { Text(primaryTitle) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || (access == .contactsOnly && selected.isEmpty))
            }
            .padding(20)
        }
        .background(Color.sBackground)
        .navigationTitle("Who can join?")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showQR) {
            VStack(spacing: 16) {
                QRCodeView(payload: link.url.absoluteString).frame(width: 260, height: 260)
                Text("Scan to open the event").foregroundStyle(Color.sMuted)
            }
            .presentationDetents([.medium])
        }
    }

    private var primaryTitle: String {
        switch access {
        case .contactsOnly: selected.isEmpty ? "Pick contacts" : "Send \(selected.count) encrypted invite\(selected.count == 1 ? "" : "s")"
        default: published ? "Done" : "Create link"
        }
    }

    private var linkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Invite link — send it any way you like")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sMuted)
            (Text("\(EventLink.host)/e/\(link.eventID)").foregroundStyle(Color.sText)
             + Text("#" + String(link.keyString.prefix(6)) + "…").foregroundStyle(Color.sAccent))
                .font(.sMono)
                .redacted(reason: published ? [] : .placeholder)
            Text("The part after # is the decryption key. It stays in the link and never reaches our server.")
                .font(.system(size: 12)).foregroundStyle(Color.sMuted)
            if published {
                HStack(spacing: 8) {
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.url = link.url
                        copied = true
                    }
                    .buttonStyle(SecondaryButtonStyle(height: 42))
                    ShareLink(item: link.url, subject: Text(details.title),
                              message: Text("You're invited to \(details.title)")) {
                        Text("Share…")
                    }
                    .buttonStyle(SecondaryButtonStyle(height: 42))
                    Button { showQR = true } label: { Image(systemName: "qrcode") }
                        .buttonStyle(SecondaryButtonStyle(height: 42))
                        .frame(width: 52)
                        .accessibilityLabel("Show as QR code")
                }
            } else {
                Text("Tap Create link to encrypt and upload the event.")
                    .font(.system(size: 13)).foregroundStyle(Color.sSecondary)
            }
        }
        .padding(14)
        .background(Color(hex: 0x14171C), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sLine))
    }

    private var contactPicker: some View {
        VStack(spacing: 0) {
            if model.contacts.isEmpty {
                Text("No contacts yet. Add some from the Contacts tab.")
                    .font(.subheadline).foregroundStyle(Color.sMuted)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(model.contacts) { contact in
                Toggle(isOn: Binding(
                    get: { selected.contains(contact.fingerprint) },
                    set: { on in if on { selected.insert(contact.fingerprint) } else { selected.remove(contact.fingerprint) } }
                )) {
                    HStack(spacing: 12) {
                        Avatar(initials: contact.initials, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name).font(.system(size: 15, weight: .medium))
                            Text(contact.fingerprint.short).font(.sMonoSmall).foregroundStyle(Color.sMuted)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                Divider().overlay(Color.sLine)
            }
        }
        .background(Color.sSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sLine))
    }

    private func primaryAction() {
        if published { onFinish(); return }
        busy = true
        errorMessage = nil
        Task {
            defer { busy = false }
            do {
                let invitees = model.contacts.filter { selected.contains($0.fingerprint) }
                try await model.publish(details, link: link, access: access, inviting: invitees)
                published = true
                if access == .contactsOnly { onFinish() }
            } catch {
                errorMessage = "Couldn't publish: \(error)"
            }
        }
    }
}
