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

    @Environment(\.modelContext) private var context

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
            Section("Appearance") {
                Picker("Appearance", selection: appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Notifications") {
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
            }

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
        do {
            try AuthService.shared.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(PreviewContainer.shared)
}
