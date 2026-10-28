import SwiftUI
import SwiftData
import FirebaseCore

@main
struct BloomApp: App {
    @StateObject private var authService = AuthService.shared
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isSignedIn {
                    ContentView()
                } else {
                    WelcomeView()
                }
            }
            .preferredColorScheme((AppAppearance(rawValue: appearanceRawValue) ?? .system).colorScheme)
            // Anything that isn't bloom://add/{uid} is ignored. A valid
            // link waits in the coordinator until the signed-in app can
            // show it, so signing in first doesn't lose it.
            .onOpenURL { url in
                ProfileLinkCoordinator.shared.handle(url)
            }
        }
        .modelContainer(for: [Note.self, Journal.self, MediaLogEntry.self])
    }
}
