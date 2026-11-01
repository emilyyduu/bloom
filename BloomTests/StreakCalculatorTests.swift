import Foundation
import Testing
@testable import Bloom

@MainActor
@Suite("Posting streak")
struct StreakCalculatorTests {
    let calendar = TestClock.utc
    // Friday 30 October 2026, mid afternoon. Today's start of day is the 30th.
    let now = TestClock.date(2026, 10, 30, 15, 0)

    private func days(_ values: [(Int, Int, Int)]) -> Set<Date> {
        Set(values.map { TestClock.startOfDay($0.0, $0.1, $0.2) })
    }

    @Test("Consecutive days up to today count one each")
    func consecutiveDays() {
        let posted = days([(2026, 10, 28), (2026, 10, 29), (2026, 10, 30)])
        #expect(StreakCalculator.currentStreak(postedDates: posted, today: now, calendar: calendar) == 3)
    }

    @Test("A streak that ended yesterday still counts")
    func endedYesterday() {
        let posted = days([(2026, 10, 27), (2026, 10, 28), (2026, 10, 29)])
        #expect(StreakCalculator.currentStreak(postedDates: posted, today: now, calendar: calendar) == 3)
    }

    @Test("A gap of a full day resets the streak to 0")
    func gapResets() {
        let posted = days([(2026, 10, 26), (2026, 10, 27), (2026, 10, 28)])
        #expect(StreakCalculator.currentStreak(postedDates: posted, today: now, calendar: calendar) == 0)
    }

    @Test("A gap inside the run stops the count at the gap")
    func gapInsideRun() {
        let posted = days([(2026, 10, 25), (2026, 10, 26), (2026, 10, 29), (2026, 10, 30)])
        #expect(StreakCalculator.currentStreak(postedDates: posted, today: now, calendar: calendar) == 2)
    }

    @Test("No posted days gives 0 and no last post date")
    func emptyInput() {
        #expect(StreakCalculator.currentStreak(postedDates: [], today: now, calendar: calendar) == 0)
        #expect(StreakCalculator.lastPostDate(postedDates: []) == nil)
    }

    @Test("Posting only today is a streak of 1, even with a time of day passed as today")
    func onlyToday() {
        let posted = days([(2026, 10, 30)])
        #expect(StreakCalculator.currentStreak(postedDates: posted, today: now, calendar: calendar) == 1)
    }

    @Test("A note at 23:59 and one at 00:00 land on different days")
    func midnightBoundary() {
        let late = calendar.startOfDay(for: TestClock.date(2026, 10, 29, 23, 59))
        let early = calendar.startOfDay(for: TestClock.date(2026, 10, 30, 0, 0))
        #expect(late != early)

        let justAfterMidnight = TestClock.date(2026, 10, 30, 0, 0)
        let streak = StreakCalculator.currentStreak(postedDates: [late, early], today: justAfterMidnight, calendar: calendar)
        #expect(streak == 2)
    }

    @Test("At 00:00 with nothing posted yet, yesterday's streak is kept")
    func freshDayKeepsYesterday() {
        let posted = days([(2026, 10, 29)])
        let streak = StreakCalculator.currentStreak(
            postedDates: posted, today: TestClock.date(2026, 10, 30, 0, 0), calendar: calendar
        )
        #expect(streak == 1)
    }

    @Test("A streak runs across a month boundary")
    func acrossMonth() {
        let posted = days([(2026, 1, 30), (2026, 1, 31), (2026, 2, 1)])
        let today = TestClock.date(2026, 2, 1, 9, 0)
        #expect(StreakCalculator.currentStreak(postedDates: posted, today: today, calendar: calendar) == 3)
    }

    @Test("A streak runs across a year boundary")
    func acrossYear() {
        let posted = days([(2025, 12, 30), (2025, 12, 31), (2026, 1, 1)])
        let today = TestClock.date(2026, 1, 1, 9, 0)
        #expect(StreakCalculator.currentStreak(postedDates: posted, today: today, calendar: calendar) == 3)
    }

    @Test("A streak runs across 29 February in a leap year")
    func acrossLeapDay() {
        let posted = days([(2028, 2, 28), (2028, 2, 29), (2028, 3, 1)])
        let today = TestClock.date(2028, 3, 1, 9, 0)
        #expect(StreakCalculator.currentStreak(postedDates: posted, today: today, calendar: calendar) == 3)
    }

    @Test("The last post date is the newest day, whatever the order")
    func lastPostDate() {
        let posted = days([(2026, 10, 3), (2026, 10, 29), (2026, 9, 30)])
        #expect(StreakCalculator.lastPostDate(postedDates: posted) == TestClock.startOfDay(2026, 10, 29))
    }
}
