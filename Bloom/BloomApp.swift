import SwiftUI
import SwiftData
import FirebaseCore

@main
struct BloomApp: App {
    @StateObject private var authService = AuthService.shared

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
        }
        .modelContainer(for: [Note.self, Journal.self])
    }
}
