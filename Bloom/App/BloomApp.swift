import SwiftUI
import SwiftData
import FirebaseAuth

@main
struct BloomApp: App {
    // Sets the notification delegate and registers the categories at launch.
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self) private var appDelegate

    init() {
        Theme.applyNavigationBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            // Without GoogleService-Info.plist Firebase is never configured, so the
            // root that creates AuthService (and so touches Auth) is never built.
            if NotificationAppDelegate.hasFirebaseConfiguration {
                BloomRootView()
            } else {
                SetupRequiredView()
            }
        }
    }
}

private struct BloomRootView: View {
    @StateObject private var authService = AuthService.shared
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue

    var body: some View {
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
        // Nav bar buttons, links and toggles use the system blue unless a tint is set.
        .tint(Theme.Colors.greenText)
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

// Shown instead of the app when GoogleService-Info.plist is missing. It touches
// no Firebase API, since Firebase was never configured.
private struct SetupRequiredView: View {
    var body: some View {
        ContentUnavailableView(
            "Setup required",
            systemImage: "gearshape",
            description: Text("Bloom needs its Firebase configuration file. Add GoogleService-Info.plist to the Bloom folder and target, then run again. See the README.")
        )
        .background(Theme.Colors.background)
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
