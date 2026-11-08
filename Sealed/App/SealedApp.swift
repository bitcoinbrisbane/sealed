import SwiftUI
import SealedCore

@main
struct SealedApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(.sAccent)
                // Universal links (https://sealed.app/e/…) and the sealed:// scheme.
                .onOpenURL { model.handle(url: $0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { model.handle(url: url) }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.phase {
            case .signedOut: WelcomeView()
            case .needsKey: KeySetupView()
            case .ready: MainTabView()
            }
        }
        .background(Color.sBackground.ignoresSafeArea())
        .sheet(item: $model.openedLink) { link in
            EventGuestView(link: link)
        }
    }
}

extension EventLink: @retroactive Identifiable {
    public var id: String { eventID }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            EventsView()
                .tabItem { Label("Events", systemImage: "calendar") }
            ContactsView()
                .tabItem { Label("Contacts", systemImage: "person.2") }
            MyKeyView()
                .tabItem { Label("My key", systemImage: "key") }
        }
    }
}
