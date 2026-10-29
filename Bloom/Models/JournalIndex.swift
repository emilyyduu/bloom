import Foundation
import SwiftUI
import Combine

// What the journal index needs from a note: when it was written, and
// whether it belongs in a journal at all (drafts never do). Adopted by my
// own Note. Friends' notes are not journaled, they only see today.
protocol JournalItem: Identifiable {
    var createdAt: Date { get }
    var isJournalEntry: Bool { get }
}

extension JournalItem {
    var isJournalEntry: Bool { true }
}

extension Note: JournalItem {
    var isJournalEntry: Bool { !isDraft }
}


struct JournalMonthKey: Hashable, Comparable, Identifiable {
    let year: Int
    let month: Int

    var id: Int { year * 100 + month }

    static func < (lhs: JournalMonthKey, rhs: JournalMonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 1)
    }

    func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
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

// Every journal note, grouped once by year, then month, then day, in a
// single pass over the notes. Each day holds its notes oldest first. A
// screen asks the index for what it shows, so no row runs a query or
// regroups anything. Drafts never get in. Nothing is stored, a journal is
// only this grouping.
struct JournalIndex<Item: JournalItem> {
    private var tree: [Int: [Int: [Int: [Item]]]] = [:]
    private var yearCounts: [Int: Int] = [:]
    private var monthCounts: [JournalMonthKey: Int] = [:]
    // Every day that has notes, oldest first, for jumping to the next or
    // previous one.
    private var sortedDays: [JournalDayKey] = []

    let calendar: Calendar

    init(items: [Item], calendar: Calendar = .current) {
        self.calendar = calendar

        for item in items where item.isJournalEntry {
            let key = JournalDayKey(item.createdAt, calendar: calendar)
            tree[key.year, default: [:]][key.month, default: [:]][key.day, default: []].append(item)
            yearCounts[key.year, default: 0] += 1
            monthCounts[key.monthKey, default: 0] += 1
        }
        for (year, months) in tree {
            for (month, days) in months {
                for (day, dayItems) in days {
                    tree[year]?[month]?[day] = dayItems.sorted { $0.createdAt < $1.createdAt }
                    sortedDays.append(JournalDayKey(year: year, month: month, day: day))
                }
            }
        }
        sortedDays.sort()
    }

    var isEmpty: Bool { sortedDays.isEmpty }
    var totalCount: Int { yearCounts.values.reduce(0, +) }

    // Newest first.
    var years: [Int] { yearCounts.keys.sorted(by: >) }

    // Only months that have notes, newest first.
    func months(in year: Int) -> [JournalMonthKey] {
        (tree[year]?.keys.sorted(by: >) ?? []).map { JournalMonthKey(year: year, month: $0) }
    }

    // The days of a month that have notes, oldest first.
    func days(in month: JournalMonthKey) -> [JournalDayKey] {
        (tree[month.year]?[month.month]?.keys.sorted() ?? []).map {
            JournalDayKey(year: month.year, month: month.month, day: $0)
        }
    }

    func count(in year: Int) -> Int { yearCounts[year] ?? 0 }
    func count(in month: JournalMonthKey) -> Int { monthCounts[month] ?? 0 }
    func count(on day: JournalDayKey) -> Int { tree[day.year]?[day.month]?[day.day]?.count ?? 0 }

    // How many days of a month have at least one note.
    func dayCount(in month: JournalMonthKey) -> Int { tree[month.year]?[month.month]?.count ?? 0 }

    // A day's notes, oldest first.
    func items(on day: JournalDayKey) -> [Item] {
        tree[day.year]?[day.month]?[day.day] ?? []
    }

    // The nearest day with notes before or after a day, which need not have
    // notes itself. nil when there is none.
    func day(before day: JournalDayKey) -> JournalDayKey? {
        sortedDays.last { $0 < day }
    }

    func day(after day: JournalDayKey) -> JournalDayKey? {
        sortedDays.first { $0 > day }
    }
}

// What the journal screens share: the index, rebuilt when the notes change.
@MainActor
final class JournalModel<Item: JournalItem>: ObservableObject {
    @Published private(set) var index = JournalIndex<Item>(items: [])

    func update(items: [Item]) {
        index = JournalIndex(items: items)
    }
}

// Shared date text, locale aware so day and month order follow the user's
// locale.
enum JournalFormat {
    static func year(_ year: Int) -> String { String(year) }

    // "October 2026"
    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    // "October"
    static func monthOnly(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide))
    }

    // "14 October"
    static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide))
    }

    // "Tuesday 14 October", the day screen's title.
    static func dayHeader(_ date: Date) -> String {
        "\(date.formatted(.dateTime.weekday(.wide))) \(dayMonth(date))"
    }

    static func noteCount(_ count: Int) -> String {
        "\(count) note\(count == 1 ? "" : "s")"
    }

    // "12 notes on 7 days"
    static func summary(notes: Int, days: Int) -> String {
        "\(noteCount(notes)) on \(days) day\(days == 1 ? "" : "s")"
    }
}
