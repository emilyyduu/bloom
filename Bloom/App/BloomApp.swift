import SwiftUI
import SwiftData
import FirebaseAuth

@main
struct BloomApp: App {
    // Sets the notification delegate and registers the categories at launch.
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self) private var appDelegate
    @StateObject private var authService = AuthService.shared
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue

//    init() {
//        FirebaseApp.configure()
//    }

    var body: some Scene {
        WindowGroup {
            Group {
                // While a log in or a new profile is being checked the main app waits and
                // WelcomeView stays mounted, so the verify screen keeps its
                // state and can show an error if the check fails.
                if let uid = authService.uid, !authService.isHoldingMainApp {
                    // One store file per account. The id makes SwiftUI
                    // rebuild the whole signed-in UI when the account
                    // changes, so every @Query and the environment
                    // context rebind to the new account's container.
                    signedInContent(uid: uid)
                } else {
                    WelcomeView()
                }
            }
            .overlay {
                if authService.isHoldingMainApp {
                    CheckingAccountView()
                }
            }
            .preferredColorScheme((AppAppearance(rawValue: appearanceRawValue) ?? .system).colorScheme)
            // Anything that isn't bloom://add/{uid} is ignored. A valid
            // link waits in the coordinator until the signed-in app can
            // show it, so signing in first doesn't lose it.
            .onOpenURL { url in
                // Firebase's phone sign in browser check comes back to the app through a
                // URL. If it's one of Firebase's, it handles it and we stop here.
                if Auth.auth().canHandle(url) { return }
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

private struct CheckingAccountView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
            Text("Checking your account")
                .textStyle(.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
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
