import Foundation
import SwiftUI
import Combine

// How the Journals screens order years, months and days.
enum JournalSortOrder: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst: return "Newest first"
        case .oldestFirst: return "Oldest first"
        }
    }

    func sorted<T: Comparable>(_ values: [T]) -> [T] {
        self == .newestFirst ? values.sorted(by: >) : values.sorted(by: <)
    }
}

struct JournalMonthKey: Hashable, Comparable, Identifiable {
    let year: Int
    let month: Int

    var id: Int { year * 100 + month }

    static func < (lhs: JournalMonthKey, rhs: JournalMonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

struct JournalDayKey: Hashable, Comparable, Identifiable {
    let year: Int
    let month: Int
    let day: Int

    var id: Int { year * 10_000 + month * 100 + day }
    var monthKey: JournalMonthKey { JournalMonthKey(year: year, month: month) }

    static func < (lhs: JournalDayKey, rhs: JournalDayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }
}

extension JournalMonthKey {
    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 1)
    }

    func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }
}

// Every posted note, grouped once by year, month and day. Built in one
// pass over the notes, so no screen runs a query or a regrouping per row.
// Drafts never get in. Journals are only this grouping, nothing is stored.
struct JournalIndex {
    // Each day's notes, oldest first.
    private(set) var notesByDay: [JournalDayKey: [Note]] = [:]
    private(set) var countByMonth: [JournalMonthKey: Int] = [:]
    private(set) var countByYear: [Int: Int] = [:]
    private var daysByMonth: [JournalMonthKey: [JournalDayKey]] = [:]
    private var monthsByYear: [Int: [JournalMonthKey]] = [:]

    let calendar: Calendar

    init(notes: [Note], calendar: Calendar = .current) {
        self.calendar = calendar

        for note in notes where !note.isDraft {
            let key = JournalDayKey(note.createdAt, calendar: calendar)
            notesByDay[key, default: []].append(note)
            countByMonth[key.monthKey, default: 0] += 1
            countByYear[key.year, default: 0] += 1
        }
        for (key, dayNotes) in notesByDay {
            notesByDay[key] = dayNotes.sorted { $0.createdAt < $1.createdAt }
            daysByMonth[key.monthKey, default: []].append(key)
        }
        for month in daysByMonth.keys {
            monthsByYear[month.year, default: []].append(month)
        }
    }

    var isEmpty: Bool { notesByDay.isEmpty }
    var earliestDay: JournalDayKey? { notesByDay.keys.min() }

    func years(_ order: JournalSortOrder) -> [Int] {
        order.sorted(Array(countByYear.keys))
    }

    func months(in year: Int, _ order: JournalSortOrder) -> [JournalMonthKey] {
        order.sorted(monthsByYear[year] ?? [])
    }

    func days(in month: JournalMonthKey, _ order: JournalSortOrder) -> [JournalDayKey] {
        order.sorted(daysByMonth[month] ?? [])
    }

    func count(on day: JournalDayKey) -> Int { notesByDay[day]?.count ?? 0 }

    func notes(on day: JournalDayKey, _ order: JournalSortOrder) -> [Note] {
        let notes = notesByDay[day] ?? []
        return order == .newestFirst ? notes.reversed() : notes
    }

    // Days with notes between two dates, both included.
    func days(from start: Date, to end: Date, _ order: JournalSortOrder) -> [JournalDayKey] {
        let first = JournalDayKey(start, calendar: calendar)
        let last = JournalDayKey(end, calendar: calendar)
        return order.sorted(notesByDay.keys.filter { $0 >= first && $0 <= last })
    }

    func noteCount(in days: [JournalDayKey]) -> Int {
        days.reduce(0) { $0 + count(on: $1) }
    }
}

// Days already in display order, grouped into months (and years) without
// another sort: the days arrive sorted, so equal neighbours belong together.
enum JournalGrouping {
    struct Month: Identifiable {
        let key: JournalMonthKey
        let days: [JournalDayKey]
        var id: Int { key.id }
    }

    struct Year: Identifiable {
        let year: Int
        let months: [Month]
        var id: Int { year }
    }

    static func months(_ days: [JournalDayKey]) -> [Month] {
        var result: [Month] = []
        for day in days {
            if let last = result.last, last.key == day.monthKey {
                result[result.count - 1] = Month(key: last.key, days: last.days + [day])
            } else {
                result.append(Month(key: day.monthKey, days: [day]))
            }
        }
        return result
    }

    static func years(_ days: [JournalDayKey]) -> [Year] {
        var result: [Year] = []
        for month in months(days) {
            if let last = result.last, last.year == month.key.year {
                result[result.count - 1] = Year(year: last.year, months: last.months + [month])
            } else {
                result.append(Year(year: month.key.year, months: [month]))
            }
        }
        return result
    }
}

// What the Journals screens share: the index, rebuilt when the notes
// change, and the sort order saved per account.
@MainActor
final class JournalModel: ObservableObject {
    @Published private(set) var index = JournalIndex(notes: [])
    @Published var sortOrder: JournalSortOrder {
        didSet { AccountDefaults.journalSortOrder = sortOrder }
    }

    init() {
        sortOrder = AccountDefaults.journalSortOrder
    }

    func update(notes: [Note]) {
        index = JournalIndex(notes: notes)
    }
}

// Shared date text, locale aware so day and month order follow the user's
// locale.
enum JournalFormat {
    private static func format(_ template: String, _ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    static func year(_ year: Int) -> String { String(year) }
    static func monthYear(_ date: Date) -> String { format("yMMMM", date) }
    static func monthOnly(_ date: Date) -> String { format("MMMM", date) }
    static func dayMonth(_ date: Date) -> String { format("dMMMM", date) }

    // "Wednesday 14 October", the day header.
    static func dayHeader(_ date: Date) -> String {
        let weekday = DateFormatter()
        weekday.locale = .current
        weekday.dateFormat = "EEEE"
        return "\(weekday.string(from: date)) \(dayMonth(date))"
    }

    static func noteCount(_ count: Int) -> String {
        "\(count) note\(count == 1 ? "" : "s")"
    }
}
