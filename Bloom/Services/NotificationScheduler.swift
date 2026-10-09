import Foundation
import UserNotifications
import SwiftData

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
    private let reminderHour = 18
    private let reminderMinute = 0

    static let title = "Bloom"
    static let body = "Anything from today worth keeping?"

    // Only called when the user turns the Daily Reminder toggle on.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // Removes every pending "bloom.reminder." request and, if the
    // setting is on and permission has been granted, schedules a fresh
    // 7 day window. Called on launch, on returning to the foreground,
    // and whenever the setting changes.
    func refreshReminders(enabled: Bool, context: ModelContext) async {
        await cancelAllReminders()
        guard enabled else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let loggedDates = loggedDates(in: context, calendar: calendar)

        for day in ReminderPlanner.reminderDays(from: today, loggedDates: loggedDates, calendar: calendar) {
            schedule(for: day, calendar: calendar)
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

    private func schedule(for day: ReminderPlanner.ReminderDay, calendar: Calendar) {
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: day.date)
        dateComponents.hour = reminderHour
        dateComponents.minute = reminderMinute

        let content = UNMutableNotificationContent()
        content.title = Self.title
        content.body = Self.body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: day.identifier, content: content, trigger: trigger)
        center.add(request)
    }

    private func loggedDates(in context: ModelContext, calendar: Calendar) -> Set<Date> {
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { !$0.isDraft })
        guard let notes = try? context.fetch(descriptor) else { return [] }
        return Set(notes.map { calendar.startOfDay(for: $0.createdAt) })
    }
}
