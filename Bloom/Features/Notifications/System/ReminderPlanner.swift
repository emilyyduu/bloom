import Foundation

// Decides which of the next 7 days (today through day 6) should get an
// evening reminder: every day except ones where a non-draft note
// already exists. Kept separate from NotificationScheduler so this
// decision can be unit tested without touching UNUserNotificationCenter.
// The daily reminder choices for one account (see AccountDefaults).
struct ReminderSettings: Equatable {
    var isEnabled: Bool
    // Minutes after midnight.
    var minutes: Int
    var adaptsToHabits: Bool
}

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

    // The least a habit needs to go on: this many notes in the last
    // `habitWindowDays` days. Below that, the chosen time is used.
    static let habitMinimumNotes = 3
    static let habitWindowDays = 30

    // The time of day (minutes after midnight) the account usually writes:
    // the median of recent notes, to the nearest 5 minutes. nil until there
    // are enough notes. `noteDates` are note creation times.
    static func habitMinutes(noteDates: [Date], now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let since = calendar.date(byAdding: .day, value: -habitWindowDays, to: now) else { return nil }
        let minutes = noteDates
            .filter { $0 >= since && $0 <= now }
            .map { calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0) }
            .sorted()
        guard minutes.count >= habitMinimumNotes else { return nil }
        let median = minutes.count.isMultiple(of: 2)
            ? (minutes[minutes.count / 2 - 1] + minutes[minutes.count / 2]) / 2
            : minutes[minutes.count / 2]
        return min(((median + 2) / 5) * 5, 24 * 60 - 1)
    }

    // The time the reminders use: the habit time when adapting and there is
    // one, otherwise the chosen time.
    static func effectiveMinutes(
        _ settings: ReminderSettings,
        noteDates: [Date],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard settings.adaptsToHabits,
              let habit = habitMinutes(noteDates: noteDates, now: now, calendar: calendar)
        else { return settings.minutes }
        return habit
    }

    // The moment a reminder fires on `day` (a start of day value).
    static func fireDate(on day: Date, minutes: Int, calendar: Calendar = .current) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
    }

    // The first planned reminder that is still in the future.
    static func nextReminder(
        loggedDates: Set<Date>,
        minutes: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        reminderDays(from: calendar.startOfDay(for: now), loggedDates: loggedDates, calendar: calendar)
            .compactMap { fireDate(on: $0.date, minutes: minutes, calendar: calendar) }
            .first { $0 > now }
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
