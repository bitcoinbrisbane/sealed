import SwiftUI
import SealedCore

struct EventsView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: EventRole = .host
    @State private var creating = false

    private var hosting: [Event] { model.events.filter { $0.role == .host } }
    private var invited: [Event] { model.events.filter { $0.role == .guest } }
    private var pending: Event? { hosting.first { $0.pendingRequests > 0 } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Show", selection: $tab) {
                        Text("Hosting").tag(EventRole.host)
                        Text(invited.isEmpty ? "Invited" : "Invited · \(invited.count)").tag(EventRole.guest)
                    }
                    .pickerStyle(.segmented)

                    if tab == .host {
                        if let pending {
                            HStack(spacing: 12) {
                                Text("\(pending.pendingRequests)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.sBackground)
                                    .frame(width: 28, height: 28)
                                    .background(Color.sAccent, in: Circle())
                                Text("requests to join **\(pending.details.title)**").font(.system(size: 14))
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Color.sMuted)
                            }
                            .padding(14)
                            .background(Color.sSuccessBg, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sSuccessLine))
                        }
                        if hosting.isEmpty {
                            empty("No events yet", "Tap + to create one. You'll get a link to share any way you like.")
                        }
                        ForEach(hosting) { EventRow(event: $0) }
                    } else {
                        if invited.isEmpty {
                            empty("No invites yet", "Open an event link someone sent you, or ask a host to invite you as a contact.")
                        }
                        ForEach(invited) { EventRow(event: $0) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .background(Color.sBackground)
            .navigationTitle("Events")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New event")
                }
            }
            .sheet(isPresented: $creating) {
                CreateEventView()
            }
        }
    }

    private func empty(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(Color.sMuted)
        }
        .card()
    }
}

struct EventRow: View {
    var event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text(event.details.startsAt, format: .dateTime.month(.abbreviated))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.sWarn)
                        .textCase(.uppercase)
                    Text(event.details.startsAt, format: .dateTime.day(.twoDigits))
                        .font(.system(size: 22, weight: .semibold))
                }
                .frame(width: 52, height: 56)
                .background(Color(hex: 0x20242B), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.details.title).font(.system(size: 17, weight: .semibold))
                    Text(event.details.startsAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(.system(size: 14)).foregroundStyle(Color.sMuted)
                }
            }
            HStack {
                Text(event.access.shortLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(hex: 0x20242B), in: RoundedRectangle(cornerRadius: 8))
                Spacer()
                Text(event.countLabel).font(.system(size: 13)).foregroundStyle(Color.sMuted)
            }
        }
        .card()
    }
}

extension EventAccess {
    var shortLabel: String {
        switch self {
        case .anyoneWithLink: "Anyone with link"
        case .requestToJoin: "Request to join"
        case .contactsOnly: "Contacts only"
        }
    }
}

extension Event {
    var countLabel: String {
        var s = "\(goingCount) going"
        if let limit = details.guestLimit { s = "\(goingCount) of \(limit) going" }
        if pendingRequests > 0 { s += " · \(pendingRequests) waiting" }
        return s
    }
}
