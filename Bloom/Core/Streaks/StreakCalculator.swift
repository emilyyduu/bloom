import Foundation

// Computes a posting streak from the set of days that have at least
// one non-draft note. Kept separate from StreakSyncService so it can
// be tested without Firestore or SwiftData.
enum StreakCalculator {
    // `postedDates` should be start-of-day values; order doesn't matter.
    // A streak counts backwards from today, but a day that simply
    // hasn't ended yet doesn't break it, so it starts from yesterday
    // instead when today has no post yet.
    static func currentStreak(postedDates: Set<Date>, today: Date, calendar: Calendar = .current) -> Int {
        guard !postedDates.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: today)
        if !postedDates.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while postedDates.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    static func lastPostDate(postedDates: Set<Date>) -> Date? {
        postedDates.max()
    }
}
