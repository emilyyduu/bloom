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

    #if DEBUG
    @AppStorage("gardenSampleDataEnabled") private var isGardenSampleDataEnabled = false
    @Query(filter: #Predicate<Note> { !$0.isDraft }) private var postedNotes: [Note]
    @Environment(\.modelContext) private var context
    @State private var sampleHistoryMessage: String?
    @State private var testBannerMessage: String?
    #endif

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
                .foregroundStyle(.red)

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

            #if DEBUG
            Section {
                Toggle("Preview garden with sample data", isOn: $isGardenSampleDataEnabled)
                Button("Add sample journal history") {
                    let count = SampleJournalHistory.add(to: context)
                    sampleHistoryMessage = "Added \(count) sample notes."
                }
                Button("Remove sample history", role: .destructive) {
                    let count = SampleJournalHistory.remove(from: context)
                    sampleHistoryMessage = "Removed \(count) sample notes."
                }
                if let sampleHistoryMessage {
                    Text(sampleHistoryMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(DebugBanner.Kind.allCases, id: \.self) { kind in
                    Button("Send test: \(kind.rawValue)") { sendTestBanner(kind) }
                }
                if let testBannerMessage {
                    Text(testBannerMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                SectionHeader("Debug")
            }
            #endif
        }
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

    #if DEBUG
    // Each test uses my newest posted note where it needs one.
    private func sendTestBanner(_ kind: DebugBanner.Kind) {
        let latestNoteID = postedNotes.max(by: { $0.createdAt < $1.createdAt })?.id.uuidString
        Task {
            testBannerMessage = await DebugBanner.schedule(kind, latestNoteID: latestNoteID)
        }
    }
    #endif

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

    init(_ title: String, subtitle: String? = nil, systemImage: String, tint: Color = .accentColor) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Color(.systemBackground))
                .frame(width: iconSize, height: iconSize)
                .background(RoundedRectangle(cornerRadius: 7).fill(tint))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
