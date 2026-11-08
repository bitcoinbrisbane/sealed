import SwiftUI
import PhotosUI
import SealedCore

struct CreateEventView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var startsAt = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var location = ""
    @State private var revealAfterApproval = true
    @State private var notes = ""
    @State private var hasLimit = true
    @State private var guestLimit = 8
    @State private var cover: PhotosPickerItem?
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PhotosPicker(selection: $cover, matching: .images) {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.title2)
                            Text(cover == nil ? "Add cover photo (encrypted)" : "Cover photo selected")
                                .font(.system(size: 15))
                        }
                        .foregroundStyle(Color.sMuted)
                        .frame(maxWidth: .infinity, minHeight: 128)
                        .background(Color(hex: 0x14171C), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color(hex: 0x343944), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    }

                    LabeledField(label: "Title") {
                        TextField("What's the occasion?", text: $title).font(.system(size: 17, weight: .medium))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Date & time").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sMuted)
                        DatePicker("Starts", selection: $startsAt, in: Date.now...)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fieldStyle()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        LabeledField(label: "Location") {
                            TextField("Address or venue", text: $location).textContentType(.fullStreetAddress)
                        }
                        Toggle("Reveal address only to approved guests", isOn: $revealAfterApproval)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sSecondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Details").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sMuted)
                        TextField("What to bring, dress code, anything guests should know", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(14)
                            .background(Color.sSurface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sLine))
                    }

                    VStack(spacing: 0) {
                        Toggle("Guest limit", isOn: $hasLimit).padding(.vertical, 4)
                        if hasLimit {
                            Stepper(value: $guestLimit, in: 1...500) {
                                Text("\(guestLimit) guests").foregroundStyle(Color.sSecondary)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .card(padding: 14)

                    Label("Details are encrypted on this phone and signed with your key before upload. The server only sees ciphertext.",
                          systemImage: "lock")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sMuted)
                }
                .padding(20)
            }
            .background(Color.sBackground)
            .navigationTitle("New event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { showShare = true }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || model.myKey == nil)
                }
            }
            .navigationDestination(isPresented: $showShare) {
                if let draft {
                    ShareEventView(details: draft, onFinish: { dismiss() })
                }
            }
        }
    }

    private var draft: EventDetails? {
        guard let me = model.myKey else { return nil }
        return EventDetails(title: title.trimmingCharacters(in: .whitespaces),
                            startsAt: startsAt,
                            location: location.nilIfEmpty,
                            revealLocationAfterApproval: revealAfterApproval,
                            notes: notes,
                            guestLimit: hasLimit ? guestLimit : nil,
                            hostName: model.myName,
                            hostFingerprint: me.publicKey.fingerprint)
        // TODO: encrypt the cover photo with the event key and upload it alongside the envelope.
    }
}
