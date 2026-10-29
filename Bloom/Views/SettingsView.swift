import SwiftUI
import SwiftData
import FirebaseAuth

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

struct SettingsView: View {
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("dailyReminderEnabled") private var isDailyReminderEnabled = false

    #if DEBUG
    @AppStorage("gardenSampleDataEnabled") private var isGardenSampleDataEnabled = false
    @State private var sampleHistoryMessage: String?
    @State private var testBannerMessage: String?
    #endif

    @Query(filter: #Predicate<Note> { $0.syncedAt == nil }) private var unsyncedNotes: [Note]
    @Query(filter: #Predicate<Note> { !$0.isDraft }) private var postedNotes: [Note]
    @Query(filter: #Predicate<Note> { !$0.isDraft && $0.sharedWithFriends }) private var sharedNotes: [Note]
    @State private var isBackingUp = false

    // Per account, see AccountDefaults.
    @AppStorage private var shareNewNotesWithFriends: Bool
    @AppStorage private var hasShownShareNewNotesConfirmation: Bool
    // Which friend activity may show a banner while Bloom is open.
    @AppStorage private var bannerFriendRequests: Bool
    @AppStorage private var bannerFriendNotes: Bool
    @AppStorage private var bannerComments: Bool
    @State private var isShowingShareNewNotesConfirmation = false
    @State private var isShowingShareAllConfirmation = false
    @State private var isShowingStopSharingAllConfirmation = false
    @State private var isBulkUpdatingSharing = false

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isShowingSignOutConfirmation = false
    @State private var errorMessage: String?
    @State private var reminderErrorMessage: String?

    init() {
        _bannerFriendRequests = AppStorage(wrappedValue: true, AccountDefaults.key(AccountDefaults.bannerFriendRequestsBase))
        _bannerFriendNotes = AppStorage(wrappedValue: true, AccountDefaults.key(AccountDefaults.bannerFriendNotesBase))
        _bannerComments = AppStorage(wrappedValue: true, AccountDefaults.key(AccountDefaults.bannerCommentsBase))
        _shareNewNotesWithFriends = AppStorage(
            wrappedValue: false, AccountDefaults.key(AccountDefaults.shareNewNotesBase)
        )
        _hasShownShareNewNotesConfirmation = AppStorage(
            wrappedValue: false, AccountDefaults.key(AccountDefaults.shareNewNotesConfirmationBase)
        )
    }

    private var appearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRawValue) ?? .system },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    // Notes still waiting on a backup for the signed-in account: ones
    // not yet stamped with an owner, plus ones already stamped with
    // this uid. A note left over from a different account on this
    // device never counts here, syncPending won't touch it either.
    private var pendingBackupCount: Int {
        let uid = Auth.auth().currentUser?.uid
        return unsyncedNotes.filter { $0.ownerUID == nil || $0.ownerUID == uid }.count
    }

    var body: some View {
        Form {
            Section {
                appearancePicker
            } header: {
                SectionHeader("Appearance")
            }

            Section {
                Toggle("Daily Reminder", isOn: $isDailyReminderEnabled)
                    .onChange(of: isDailyReminderEnabled) { _, isEnabled in
                        handleReminderToggle(isEnabled)
                    }
                FormErrorText(message: reminderErrorMessage)
                PhoneAlertsSettingsRows()

                #if DEBUG
                Button("Send Test Notification (5s)") {
                    NotificationScheduler.shared.sendTestNotification()
                }
                #endif
            } header: {
                SectionHeader("Notifications")
            }

            Section {
                Toggle("Friend requests", isOn: $bannerFriendRequests)
                Toggle("Friends\u{2019} new notes", isOn: $bannerFriendNotes)
                Toggle("Comments on my notes", isOn: $bannerComments)
            } header: {
                SectionHeader("Banners")
            } footer: {
                Text("Banners appear at the top while Bloom is open. The notifications screen always shows everything.")
            }

            Section {
                Text(backupStatusText)
                    .foregroundStyle(.secondary)
                Button("Back up now") {
                    backUpNow()
                }
                .disabled(isBackingUp || pendingBackupCount == 0)
            } header: {
                SectionHeader("Backup")
            }

            Section {
                Toggle("Share new notes with friends", isOn: $shareNewNotesWithFriends)
                    .onChange(of: shareNewNotesWithFriends) { _, isOn in
                        guard isOn, !hasShownShareNewNotesConfirmation else { return }
                        isShowingShareNewNotesConfirmation = true
                    }

                Button("Share all my past notes") {
                    isShowingShareAllConfirmation = true
                }
                .disabled(isBulkUpdatingSharing || postedNotes.isEmpty)

                Button("Stop sharing all notes", role: .destructive) {
                    isShowingStopSharingAllConfirmation = true
                }
                .disabled(isBulkUpdatingSharing || sharedNotes.isEmpty)
            } footer: {
                Text("All your friends can read notes you share. You can change this for any note.")
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

            Section {
                Button("Sign Out", role: .destructive) {
                    isShowingSignOutConfirmation = true
                }
                FormErrorText(message: errorMessage)
            }
        }
        .navigationTitle("Settings")
        .refreshesNotificationPermission()
        .alert(
            "Share new notes with friends",
            isPresented: $isShowingShareNewNotesConfirmation
        ) {
            Button("OK") { hasShownShareNewNotesConfirmation = true }
        } message: {
            Text("All your friends can read notes you share. You can change this for any note.")
        }
        .confirmationDialog(
            "Share all \(postedNotes.count) note\(postedNotes.count == 1 ? "" : "s")?",
            isPresented: $isShowingShareAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Share All") { bulkSetSharing(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All your accepted friends will be able to read these notes.")
        }
        .confirmationDialog(
            "Stop sharing \(sharedNotes.count) note\(sharedNotes.count == 1 ? "" : "s")?",
            isPresented: $isShowingStopSharingAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Sharing", role: .destructive) { bulkSetSharing(false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your friends will no longer be able to read these notes.")
        }
        .confirmationDialog(
            "Sign out of Bloom?",
            isPresented: $isShowingSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) { signOut() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var backupStatusText: String {
        pendingBackupCount == 0
            ? "All notes backed up"
            : "\(pendingBackupCount) note\(pendingBackupCount == 1 ? "" : "s") waiting to back up"
    }

    // The segmented style truncates "System"/"Light"/"Dark" at
    // accessibility sizes, so it becomes a menu instead, same as the
    // Journal segmented control.
    @ViewBuilder
    private var appearancePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Appearance", selection: appearance) {
                ForEach(AppAppearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        } else {
            Picker("Appearance", selection: appearance) {
                ForEach(AppAppearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func handleReminderToggle(_ isEnabled: Bool) {
        reminderErrorMessage = nil

        guard isEnabled else {
            Task { await NotificationScheduler.shared.refreshReminders(enabled: false, context: context) }
            return
        }

        Task {
            let granted = await NotificationScheduler.shared.requestAuthorization()
            if granted {
                await NotificationScheduler.shared.refreshReminders(enabled: true, context: context)
            } else {
                isDailyReminderEnabled = false
                reminderErrorMessage = "Bloom needs notification permission for reminders. " +
                    "Turn it on in iOS Settings > Bloom > Notifications."
            }
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

    private func backUpNow() {
        guard !isBackingUp else { return }
        isBackingUp = true
        Task {
            await NoteSyncService.shared.syncPending(context: context)
            isBackingUp = false
        }
    }

    private func bulkSetSharing(_ isShared: Bool) {
        guard !isBulkUpdatingSharing else { return }
        isBulkUpdatingSharing = true
        Task {
            await NoteSyncService.shared.setSharedWithFriendsForAllNotes(isShared, context: context)
            isBulkUpdatingSharing = false
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

#Preview("Dynamic Type - Large") {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(PreviewContainer.shared)
    .environment(\.dynamicTypeSize, .large)
}

#Preview("Dynamic Type - XXX Large") {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(PreviewContainer.shared)
    .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Dynamic Type - Accessibility 5") {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(PreviewContainer.shared)
    .environment(\.dynamicTypeSize, .accessibility5)
}
