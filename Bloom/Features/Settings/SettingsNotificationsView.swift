import SwiftUI
import SwiftData

// Settings > Notifications: whether iOS allows alerts, the daily reminder
// (a fixed time, or one learned from when the account writes) and which
// friend activity is shown as a notification. Everything here is per
// account, see AccountDefaults.
struct SettingsNotificationsView: View {
    @Query(filter: #Predicate<Note> { !$0.isDraft }) private var postedNotes: [Note]
    @Environment(\.modelContext) private var context

    private let manager = NotificationManager.shared

    // Per account.
    @AppStorage private var isReminderEnabled: Bool
    @AppStorage private var reminderMinutes: Int
    @AppStorage private var adaptsToHabits: Bool
    @AppStorage private var notifyFriendRequests: Bool
    @AppStorage private var notifyFriendNotes: Bool
    @AppStorage private var notifyComments: Bool
    @AppStorage private var notifyReactions: Bool

    @State private var reminderErrorMessage: String?

    init() {
        typealias D = AccountDefaults
        _isReminderEnabled = AppStorage(wrappedValue: D.dailyReminderEnabledDefault, D.key(D.dailyReminderEnabledBase))
        _reminderMinutes = AppStorage(wrappedValue: D.defaultReminderMinutes, D.key(D.reminderTimeMinutesBase))
        _adaptsToHabits = AppStorage(wrappedValue: false, D.key(D.reminderAdaptBase))
        _notifyFriendRequests = AppStorage(wrappedValue: D.notifyDefault(D.notifyFriendRequestsBase), D.key(D.notifyFriendRequestsBase))
        _notifyFriendNotes = AppStorage(wrappedValue: D.notifyDefault(D.notifyFriendNotesBase), D.key(D.notifyFriendNotesBase))
        _notifyComments = AppStorage(wrappedValue: D.notifyDefault(D.notifyCommentsBase), D.key(D.notifyCommentsBase))
        _notifyReactions = AppStorage(wrappedValue: D.notifyDefault(D.notifyReactionsBase), D.key(D.notifyReactionsBase))
    }

    private var reminderSettings: ReminderSettings {
        ReminderSettings(isEnabled: isReminderEnabled, minutes: reminderMinutes, adaptsToHabits: adaptsToHabits)
    }

    private var noteDates: [Date] { postedNotes.map(\.createdAt) }

    // What the reminders really use: the habit time while adapting (once
    // there are enough notes), otherwise the chosen time.
    private var shownMinutes: Int {
        ReminderPlanner.effectiveMinutes(reminderSettings, noteDates: noteDates)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                ReminderPlanner.fireDate(on: Calendar.current.startOfDay(for: Date()), minutes: shownMinutes) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminderMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var nextReminderText: String? {
        guard isReminderEnabled, manager.canScheduleNotifications else { return nil }
        let calendar = Calendar.current
        let logged = Set(noteDates.map { calendar.startOfDay(for: $0) })
        guard let next = ReminderPlanner.nextReminder(loggedDates: logged, minutes: shownMinutes) else {
            return "Next reminder: none in the next 7 days"
        }
        let time = next.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(next) { return "Next reminder: \(time)" }
        if calendar.isDateInTomorrow(next) { return "Next reminder: Tomorrow, \(time)" }
        return "Next reminder: \(next.formatted(.dateTime.weekday(.wide))), \(time)"
    }

    var body: some View {
        Form {
            permissionSection
            reminderSection
            friendActivitySection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .refreshesNotificationPermission()
        // Any change to the reminder replaces the pending notifications
        // at once. The values are already saved when these run.
        .onChange(of: reminderMinutes) { _, _ in rescheduleReminders() }
        .onChange(of: adaptsToHabits) { _, _ in rescheduleReminders() }
    }

    // MARK: - Permission

    private var permissionSection: some View {
        Section {
            LabeledContent("Notifications", value: manager.hasChecked ? manager.authorizationDescription : "Checking")
            if manager.hasChecked {
                switch manager.authorizationStatus {
                case .notDetermined:
                    Button("Turn on") {
                        Task {
                            await manager.requestAuthorization()
                            await NotificationScheduler.shared.refreshReminders(context: context)
                        }
                    }
                    .frame(minHeight: 44, alignment: .leading)
                case .denied:
                    Button("Open Settings") { manager.openSettings() }
                        .frame(minHeight: 44, alignment: .leading)
                default:
                    EmptyView()
                }
            }
        } header: {
            SectionHeader("Permission")
        }
    }

    // MARK: - Daily reminder

    private var reminderSection: some View {
        Section {
            Toggle("Daily reminder", isOn: $isReminderEnabled)
                .onChange(of: isReminderEnabled) { _, isOn in handleReminderToggle(isOn) }

            if let reminderErrorMessage {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    FormErrorText(message: reminderErrorMessage)
                    Button("Open Settings") { manager.openSettings() }
                }
                .frame(minHeight: 44, alignment: .leading)
            }

            if isReminderEnabled {
                Toggle("Adapt to my habits", isOn: $adaptsToHabits)

                DatePicker("Reminder time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .disabled(adaptsToHabits)

                if adaptsToHabits {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Bloom picks the time from when you usually write")
                        if let nextReminderText { Text(nextReminderText) }
                        if ReminderPlanner.habitMinutes(noteDates: noteDates) == nil {
                            Text("Until you have written a few notes, Bloom uses the time you chose.")
                        }
                    }
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        } header: {
            SectionHeader("Daily reminder")
        } footer: {
            Text("Bloom reminds you to write a note if you haven\u{2019}t added one that day.")
        }
    }

    // MARK: - Friend activity

    private var friendActivitySection: some View {
        Section {
            Toggle("Friend requests", isOn: $notifyFriendRequests)
            Toggle("Friends\u{2019} new notes", isOn: $notifyFriendNotes)
            Toggle("Comments and replies", isOn: $notifyComments)
            Toggle("Reactions", isOn: $notifyReactions)
        } header: {
            SectionHeader("Friend activity")
        } footer: {
            Text("Friend alerts arrive while Bloom is open or has recently been open.")
        }
    }

    // MARK: - Actions

    private func rescheduleReminders() {
        guard isReminderEnabled else { return }
        Task { await NotificationScheduler.shared.refreshReminders(context: context) }
    }

    // Turning it on asks for permission in context the first time. If
    // iOS says no, the switch goes back off and says how to fix it.
    private func handleReminderToggle(_ isOn: Bool) {
        reminderErrorMessage = nil

        guard isOn else {
            Task { await NotificationScheduler.shared.refreshReminders(context: context) }
            return
        }

        Task {
            let granted = await NotificationScheduler.shared.requestAuthorization()
            await manager.refresh()
            if granted {
                await NotificationScheduler.shared.refreshReminders(context: context)
            } else {
                isReminderEnabled = false
                reminderErrorMessage = "Bloom needs notification permission for reminders. " +
                    "Turn it on in iOS Settings > Bloom > Notifications."
            }
        }
    }
}

#Preview("Light") {
    NavigationStack { SettingsNotificationsView() }
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark Accessibility 5") {
    NavigationStack { SettingsNotificationsView() }
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}
