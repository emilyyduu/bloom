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
    #endif

    @Query(filter: #Predicate<Note> { $0.syncedAt == nil }) private var unsyncedNotes: [Note]
    @Query(filter: #Predicate<Note> { !$0.isDraft }) private var postedNotes: [Note]
    @Query(filter: #Predicate<Note> { !$0.isDraft && $0.sharedWithFriends }) private var sharedNotes: [Note]
    @State private var isBackingUp = false

    @AppStorage("shareNewNotesWithFriends") private var shareNewNotesWithFriends = false
    @AppStorage("hasShownShareNewNotesConfirmation") private var hasShownShareNewNotesConfirmation = false
    @State private var isShowingShareNewNotesConfirmation = false
    @State private var isShowingShareAllConfirmation = false
    @State private var isShowingStopSharingAllConfirmation = false
    @State private var isBulkUpdatingSharing = false

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isShowingSignOutConfirmation = false
    @State private var errorMessage: String?
    @State private var reminderErrorMessage: String?

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

                #if DEBUG
                Button("Send Test Notification (5s)") {
                    NotificationScheduler.shared.sendTestNotification()
                }
                #endif
            } header: {
                SectionHeader("Notifications")
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
                Text("Everyone in your circle can read notes you share. You can change this for any note.")
            }

            #if DEBUG
            Section {
                Toggle("Preview garden with sample data", isOn: $isGardenSampleDataEnabled)
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
        .alert(
            "Share new notes with friends",
            isPresented: $isShowingShareNewNotesConfirmation
        ) {
            Button("OK") { hasShownShareNewNotesConfirmation = true }
        } message: {
            Text("Everyone in your circle can read notes you share. You can change this for any note.")
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
        FriendService.shared.stopListening()
        GardenService.shared.stopListening()
        SharedNotesStore.shared.stopListening()
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
