import SwiftUI
import SwiftData
import FirebaseCore

@main
struct BloomApp: App {
    // Sets the notification delegate and registers the categories at launch.
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self) private var appDelegate
    @StateObject private var authService = AuthService.shared
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue

    init() {
        FirebaseApp.configure()
        for family in UIFont.familyNames where family.contains("DM") {
            print(family, UIFont.fontNames(forFamilyName: family))
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let uid = authService.uid {
                    // One store file per account. The id makes SwiftUI
                    // rebuild the whole signed-in UI when the account
                    // changes, so every @Query and the environment
                    // context rebind to the new account's container.
                    signedInContent(uid: uid)
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
    }

    @ViewBuilder
    private func signedInContent(uid: String) -> some View {
        if let container = Self.container(for: uid) {
            ContentView()
                .modelContainer(container)
                .id(uid)
        } else {
            StoreUnavailableView()
        }
    }

    private static func container(for uid: String) -> ModelContainer? {
        do {
            return try StoreManager.shared.container(for: uid)
        } catch {
            return nil
        }
    }
}

// Shown only if an account's store file can't be opened, so notes are
// never silently written somewhere else.
private struct StoreUnavailableView: View {
    var body: some View {
        ContentUnavailableView(
            "Can't open your notes",
            systemImage: "exclamationmark.triangle",
            description: Text("Close Bloom and open it again. If this keeps happening, sign out and sign back in.")
        )
    }
}
