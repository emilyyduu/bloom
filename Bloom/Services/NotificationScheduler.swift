import Foundation
import UserNotifications
import SwiftData
import FirebaseAuth

// Schedules Bloom's evening reminder. A local notification can't check
// at delivery time whether a note was logged today, so instead of one
// repeating trigger this schedules up to 7 individual notifications,
// one per day, each with its own "bloom.reminder.yyyy-MM-dd" identifier
// (see ReminderPlanner), and skips any day that already has a note.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private init() {}

    private let center = UNUserNotificationCenter.current()
    static let title = "Bloom"
    static let body = "Anything from today worth keeping?"

    // Called when the user turns the Daily Reminder on, or taps Turn on
    // in Notifications settings. Never at launch.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // Removes every pending "bloom.reminder." request and, if the
    // account's reminder is on and permission has been granted, schedules
    // a fresh 7 day window at the chosen time (or the habit time when
    // "Adapt to my habits" is on). Called on launch, on returning to the
    // foreground, and whenever a reminder setting changes.
    func refreshReminders(context: ModelContext) async {
        await cancelAllReminders()
        guard AccountDefaults.reminderSettings.isEnabled else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        // Only plan from the signed-in account's own store, and only if
        // that account is still signed in after the awaits above.
        guard StoreManager.shared.owns(context, uid: Auth.auth().currentUser?.uid) else { return }

        // Read after the awaits so a change made meanwhile is honoured.
        let reminder = AccountDefaults.reminderSettings
        guard reminder.isEnabled else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let noteDates = postedNoteDates(in: context)
        let loggedDates = Set(noteDates.map { calendar.startOfDay(for: $0) })
        let minutes = ReminderPlanner.effectiveMinutes(reminder, noteDates: noteDates, calendar: calendar)

        for day in ReminderPlanner.reminderDays(from: today, loggedDates: loggedDates, calendar: calendar) {
            schedule(for: day, minutes: minutes, calendar: calendar)
        }
    }

    // Cancels just today's pending reminder. Called the moment a note
    // is saved to today's journal, since that day no longer needs one.
    func cancelTodaysReminder() {
        let identifier = ReminderPlanner.identifier(for: Calendar.current.startOfDay(for: Date()))
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelAllReminders() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) }
        NotificationLog.removed("removePendingNotificationRequests (cancelAllReminders)", identifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    // DEBUG-only: fires 5 seconds after it's called, so delivery can be
    // checked without waiting until 6pm.
    
    func sendTestNotification() {
        let content = UNMutableNotificationContent(
        )
        content.title = Self.title
        content.body = Self.body
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 5,
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier:"bloom.reminder.test",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    private func schedule(for day: ReminderPlanner.ReminderDay, minutes: Int, calendar: Calendar) {
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: day.date)
        dateComponents.hour = minutes / 60
        dateComponents.minute = minutes % 60

        let content = UNMutableNotificationContent()
        content.title = Self.title
        content.body = Self.body
        content.sound = .default
        content.categoryIdentifier = NotificationConstants.Category.reminder
        if let uid = Auth.auth().currentUser?.uid {
            content.userInfo = [NotificationConstants.Key.recipientUID: uid]
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: day.identifier, content: content, trigger: trigger)
        center.add(request) { error in
            Task { @MainActor in NotificationLog.added(request, error: error) }
        }
    }

    // When each posted note was written.
    private func postedNoteDates(in context: ModelContext) -> [Date] {
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { !$0.isDraft })
        guard let notes = try? context.fetch(descriptor) else { return [] }
        return notes.map(\.createdAt)
    }
}
