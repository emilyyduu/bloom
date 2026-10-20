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

struct SettingsView: View {
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("dailyReminderEnabled") private var isDailyReminderEnabled = false

    #if DEBUG
    @AppStorage("gardenSampleDataEnabled") private var isGardenSampleDataEnabled = false
    #endif

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

            #if DEBUG
            Section {
                Toggle("Preview garden with sample data", isOn: $isGardenSampleDataEnabled)
                RealityKitSpikeEntryRow()
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
        .confirmationDialog(
            "Sign out of Bloom?",
            isPresented: $isShowingSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) { signOut() }
            Button("Cancel", role: .cancel) {}
        }
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

    private func signOut() {
        FriendService.shared.stopListening()
        GardenService.shared.stopListening()
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
