import Foundation

// Decides which of the next 7 days (today through day 6) should get an
// evening reminder: every day except ones where a non-draft note
// already exists. Kept separate from NotificationScheduler so this
// decision can be unit tested without touching UNUserNotificationCenter.
enum ReminderPlanner {
    struct ReminderDay: Equatable {
        let date: Date
        let identifier: String
    }

    static let identifierPrefix = "bloom.reminder."

    // `today` and the dates in `loggedDates` should all be start-of-day
    // values in the same calendar.
    static func reminderDays(
        from today: Date,
        loggedDates: Set<Date>,
        calendar: Calendar = .current
    ) -> [ReminderDay] {
        (0..<7).compactMap { offset -> ReminderDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            guard !loggedDates.contains(date) else { return nil }
            return ReminderDay(date: date, identifier: identifier(for: date, calendar: calendar))
        }
    }

    static func identifier(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return identifierPrefix + formatter.string(from: date)
    }
}
