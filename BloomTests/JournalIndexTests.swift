import Foundation
import Testing
@testable import Bloom

// A stand-in for Note, so the index is tested without SwiftData.
@MainActor
private struct TestItem: JournalItem {
    let id = UUID()
    let createdAt: Date
    var isJournalEntry = true
}

@MainActor
@Suite("Journal index")
struct JournalIndexTests {
    let calendar = TestClock.utc

    private func item(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0,
                      draft: Bool = false) -> TestItem {
        TestItem(createdAt: TestClock.date(year, month, day, hour, minute, second), isJournalEntry: !draft)
    }

    private func index(_ items: [TestItem]) -> JournalIndex<TestItem> {
        JournalIndex(items: items, calendar: calendar)
    }

    @Test("An empty list gives an empty index")
    func empty() {
        let index = index([])
        #expect(index.isEmpty)
        #expect(index.totalCount == 0)
        #expect(index.years.isEmpty)
        #expect(index.months(in: 2026).isEmpty)
        #expect(index.count(in: 2026) == 0)
        #expect(index.items(on: JournalDayKey(year: 2026, month: 1, day: 1)).isEmpty)
    }

    @Test("Notes group by year, month and day, newest years and months first")
    func grouping() {
        let index = index([
            item(2025, 12, 31), item(2026, 1, 1), item(2026, 1, 1, 18), item(2026, 3, 5), item(2026, 3, 9),
        ])
        #expect(index.years == [2026, 2025])
        #expect(index.months(in: 2026) == [JournalMonthKey(year: 2026, month: 3), JournalMonthKey(year: 2026, month: 1)])
        #expect(index.months(in: 2025) == [JournalMonthKey(year: 2025, month: 12)])
        #expect(index.days(in: JournalMonthKey(year: 2026, month: 3)).map(\.day) == [5, 9])
        #expect(index.days(in: JournalMonthKey(year: 2026, month: 1)).map(\.day) == [1])
        #expect(index.months(in: 1999).isEmpty)
    }

    @Test("Counts are right at every level")
    func counts() {
        let index = index([
            item(2025, 12, 31), item(2026, 1, 1), item(2026, 1, 1, 18), item(2026, 3, 5), item(2026, 3, 9),
        ])
        let january = JournalMonthKey(year: 2026, month: 1)
        let march = JournalMonthKey(year: 2026, month: 3)
        #expect(index.totalCount == 5)
        #expect(index.count(in: 2026) == 4)
        #expect(index.count(in: 2025) == 1)
        #expect(index.count(in: january) == 2)
        #expect(index.count(in: march) == 2)
        #expect(index.count(on: JournalDayKey(year: 2026, month: 1, day: 1)) == 2)
        #expect(index.dayCount(in: january) == 1)
        #expect(index.dayCount(in: march) == 2)
        #expect(index.count(on: JournalDayKey(year: 2026, month: 1, day: 2)) == 0)
    }

    @Test("A day's notes come out oldest first whatever order they went in")
    func dayOrdering() {
        let evening = item(2026, 10, 14, 20)
        let morning = item(2026, 10, 14, 7)
        let noon = item(2026, 10, 14, 12)
        let index = index([evening, morning, noon])
        let day = JournalDayKey(year: 2026, month: 10, day: 14)
        #expect(index.items(on: day).map(\.id) == [morning.id, noon.id, evening.id])
    }

    @Test("Drafts never get in")
    func draftsExcluded() {
        let index = index([item(2026, 10, 14), item(2026, 10, 14, 15, draft: true), item(2026, 10, 20, draft: true)])
        #expect(index.totalCount == 1)
        #expect(index.days(in: JournalMonthKey(year: 2026, month: 10)).map(\.day) == [14])
        #expect(index.dayCount(in: JournalMonthKey(year: 2026, month: 10)) == 1)
    }

    @Test("A note at 00:00 belongs to the new day and 23:59:59 to the old one")
    func midnight() {
        let late = item(2026, 1, 31, 23, 59, 59)
        let midnight = item(2026, 2, 1, 0, 0, 0)
        let index = index([late, midnight])
        #expect(index.items(on: JournalDayKey(year: 2026, month: 1, day: 31)).map(\.id) == [late.id])
        #expect(index.items(on: JournalDayKey(year: 2026, month: 2, day: 1)).map(\.id) == [midnight.id])
        #expect(index.months(in: 2026).count == 2)
    }

    @Test("The same instant lands on different days for different calendars")
    func timeZoneGrouping() {
        // 23:30 UTC on 14 October is 10:30 on 15 October in Sydney.
        let note = TestItem(createdAt: TestClock.date(2026, 10, 14, 23, 30))
        let utcIndex = JournalIndex(items: [note], calendar: TestClock.utc)
        let sydneyIndex = JournalIndex(items: [note], calendar: TestClock.calendar(timeZone: "Australia/Sydney"))
        #expect(utcIndex.count(on: JournalDayKey(year: 2026, month: 10, day: 14)) == 1)
        #expect(sydneyIndex.count(on: JournalDayKey(year: 2026, month: 10, day: 15)) == 1)
    }

    @Test("Finding the nearest day before or after, across months and years")
    func neighbouringDays() {
        let index = index([item(2025, 12, 30), item(2026, 1, 2), item(2026, 3, 5)])
        let jan2 = JournalDayKey(year: 2026, month: 1, day: 2)
        #expect(index.day(before: jan2) == JournalDayKey(year: 2025, month: 12, day: 30))
        #expect(index.day(after: jan2) == JournalDayKey(year: 2026, month: 3, day: 5))
        #expect(index.day(before: JournalDayKey(year: 2025, month: 12, day: 30)) == nil)
        #expect(index.day(after: JournalDayKey(year: 2026, month: 3, day: 5)) == nil)
        // A day with no notes still finds its neighbours.
        #expect(index.day(after: JournalDayKey(year: 2026, month: 2, day: 1)) == JournalDayKey(year: 2026, month: 3, day: 5))
    }

    @Test("Day and month keys compare in date order and build ids")
    func keys() {
        #expect(JournalDayKey(year: 2025, month: 12, day: 31) < JournalDayKey(year: 2026, month: 1, day: 1))
        #expect(JournalMonthKey(year: 2026, month: 2) < JournalMonthKey(year: 2026, month: 10))
        #expect(JournalDayKey(year: 2026, month: 10, day: 5).id == 2026_10_05)
        #expect(JournalMonthKey(year: 2026, month: 10).id == 202610)
        #expect(JournalDayKey(year: 2026, month: 10, day: 5).monthKey == JournalMonthKey(year: 2026, month: 10))
    }

    @Test("A key built from a date can give the date back")
    func keyRoundTrip() {
        let date = TestClock.date(2026, 10, 14, 15, 45)
        let day = JournalDayKey(date, calendar: calendar)
        #expect(day == JournalDayKey(year: 2026, month: 10, day: 14))
        #expect(day.date(calendar: calendar) == TestClock.startOfDay(2026, 10, 14))
        #expect(JournalMonthKey(date, calendar: calendar).date(calendar: calendar) == TestClock.startOfDay(2026, 10, 1))
    }

    @Test("Note counts and summaries use the right plurals", arguments: [
        (0, "0 notes"), (1, "1 note"), (2, "2 notes"),
    ])
    func noteCountText(count: Int, expected: String) {
        #expect(JournalFormat.noteCount(count) == expected)
    }

    @Test("Summaries read '12 notes on 7 days'")
    func summaryText() {
        #expect(JournalFormat.summary(notes: 12, days: 7) == "12 notes on 7 days")
        #expect(JournalFormat.summary(notes: 1, days: 1) == "1 note on 1 day")
    }
}
