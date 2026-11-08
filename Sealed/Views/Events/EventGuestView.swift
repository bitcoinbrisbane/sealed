import SwiftUI
import SealedCore

/// What someone sees after opening a Sealed link.
struct EventGuestView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let link: EventLink

    enum LoadState { case loading, notFound, failed(String), loaded(AppModel.OpenedEvent) }
    @State private var state: LoadState = .loading
    @State private var requestSent = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    ProgressView("Decrypting…").frame(maxWidth: .infinity, maxHeight: .infinity)
                case .notFound:
                    message("Event not found", "It may have been deleted, or the link is incomplete.")
                case .failed(let reason):
                    message("Couldn't open this event", reason)
                case .loaded(let opened):
                    content(opened)
                }
            }
            .background(Color.sBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            if let opened = try await model.open(link) { state = .loaded(opened) } else { state = .notFound }
        } catch {
            // Wrong key or tampered ciphertext both fail authentication here.
            state = .failed("The link's key doesn't match this event, or the data was altered.")
        }
    }

    private func content(_ opened: AppModel.OpenedEvent) -> some View {
        let d = opened.details
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color(hex: 0x1B2A26))
                    .frame(height: 180)
                    .overlay(alignment: .bottomLeading) {
                        Text("Cover photo · decrypted on device")
                            .font(.caption).foregroundStyle(Color.sSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            .padding(16)
                    }
                    .padding(.horizontal, -20)

                VStack(alignment: .leading, spacing: 6) {
                    Text(d.title).font(.system(size: 28, weight: .semibold))
                    Text(d.startsAt, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                        .font(.system(size: 15)).foregroundStyle(Color.sSecondary)
                }

                HStack(spacing: 12) {
                    Avatar(initials: String(d.hostName.prefix(2)).uppercased(), size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hosted by \(d.hostName)").font(.system(size: 15, weight: .medium))
                        Text(d.hostFingerprint.short + " · signed").font(.sMonoSmall).foregroundStyle(Color.sMuted)
                    }
                    Spacer()
                    if opened.hostVerified {
                        Label("Verified", systemImage: "checkmark").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.sAccent)
                    } else {
                        Text("Not a contact").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.sWarn)
                    }
                }
                .card(padding: 14)

                Label(d.location ?? "Address revealed once the host approves you", systemImage: "mappin.and.ellipse")
                    .font(.system(size: 15)).foregroundStyle(Color.sSecondary)
                if let limit = d.guestLimit {
                    Label("Up to \(limit) guests", systemImage: "person.2")
                        .font(.system(size: 15)).foregroundStyle(Color.sSecondary)
                }
                if !d.notes.isEmpty {
                    Text(d.notes).font(.system(size: 15)).foregroundStyle(Color.sMuted)
                }

                if requestSent {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Request sent").font(.system(size: 16, weight: .semibold))
                        Text("You'll be notified when \(d.hostName) approves. The address unlocks then.")
                            .font(.system(size: 14)).foregroundStyle(Color.sSecondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.sSuccessBg, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sSuccessLine))
                } else {
                    VStack(spacing: 10) {
                        Button {
                            busy = true
                            Task {
                                defer { busy = false }
                                if (try? await model.requestToJoin(link)) != nil { requestSent = true }
                            }
                        } label: { Text("Request to join") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(busy || model.myKey == nil)

                        Text(model.myKey == nil
                             ? "Sign in and set up your key to request a spot."
                             : "Your request is signed with your key so the host knows it's really you.")
                            .font(.footnote).foregroundStyle(Color.sMuted).multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func message(_ title: String, _ body: String) -> some View {
        ContentUnavailableView(title, systemImage: "lock.slash", description: Text(body))
    }
}
