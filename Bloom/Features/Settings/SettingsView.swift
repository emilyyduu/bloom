import SwiftUI
import SwiftData

// Stored with @AppStorage and applied at the app root in BloomApp, so
// it takes effect everywhere, not just while Settings is on screen.
enum AppAppearance: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// The Settings home: a grouped list of rows, each opening its own screen
// (Display, Notifications, Privacy, About), plus Account. Pushed from the
// Profile tab's NavigationStack.
struct SettingsView: View {
    // What Edit profile needs, loaded by ProfileView.
    var displayName = ""
    var username = ""
    var isProfileLoading = false
    var onProfileSaved: (_ displayName: String, _ username: String) -> Void = { _, _ in }

    @State private var isShowingSignOutConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    EditProfileView(displayName: displayName, username: username, onSave: onProfileSaved)
                } label: {
                    SettingsRowLabel("Edit profile", subtitle: "Name, username and photo", systemImage: "person.crop.circle")
                }
                .disabled(isProfileLoading)

                Button(role: .destructive) {
                    isShowingSignOutConfirmation = true
                } label: {
                    SettingsRowLabel("Sign out", systemImage: "rectangle.portrait.and.arrow.right", tint: .red)
                }
                .foregroundStyle(Theme.Colors.error)

                FormErrorText(message: errorMessage)
            } header: {
                SectionHeader("Account")
            }

            Section {
                NavigationLink {
                    SettingsDisplayView()
                } label: {
                    SettingsRowLabel("Display", subtitle: "Appearance and text size", systemImage: "textformat.size")
                }
                NavigationLink {
                    SettingsNotificationsView()
                } label: {
                    SettingsRowLabel("Notifications", subtitle: "Reminder and friend alerts", systemImage: "bell")
                }
                NavigationLink {
                    SettingsPrivacyView()
                } label: {
                    SettingsRowLabel("Privacy", subtitle: "Sharing, permissions and backup", systemImage: "hand.raised")
                }
                NavigationLink {
                    AboutView()
                } label: {
                    SettingsRowLabel("About", subtitle: AppInfo.versionLine, systemImage: "info.circle")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle("Settings")
        .confirmationDialog(
            "Sign out of Bloom?",
            isPresented: $isShowingSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) { signOut() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func signOut() {
        AuthService.shared.resetInMemoryAccountState()
        do {
            try AuthService.shared.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// A settings row: the SF Symbol in a rounded square, a title and an
// optional one line subtitle. Grows with Dynamic Type, the text wraps.
struct SettingsRowLabel: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 30

    init(_ title: String, subtitle: String? = nil, systemImage: String, tint: Color = Theme.Colors.actionFill) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .textStyle(.callout)
                .foregroundStyle(Theme.Colors.surface)
                .frame(width: iconSize, height: iconSize)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .textStyle(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .frame(minHeight: 44)
    }
}

#Preview("Light") {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(PreviewContainer.shared)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(PreviewContainer.shared)
    .preferredColorScheme(.dark)
}

#Preview("Dynamic Type - Accessibility 5") {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(PreviewContainer.shared)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Landscape", traits: .landscapeLeft) {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(PreviewContainer.shared)
}
