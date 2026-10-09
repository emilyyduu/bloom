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
        }
        .modelContainer(for: [Note.self, Journal.self])
    }
}
