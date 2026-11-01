import Foundation
import Testing
@testable import Bloom

@MainActor
@Suite("Plant growth state")
struct GrowthStateTests {
    let calendar = TestClock.utc
    let today = TestClock.date(2026, 10, 30, 15, 0)

    @Test("Days since the last note map to blooming, wilting or dead", arguments: [
        (0, PlantState.blooming), (1, .blooming),
        (2, .wilting), (3, .wilting), (4, .wilting),
        (5, .dead), (6, .dead), (30, .dead),
    ])
    func stateForDaysSince(days: Int, expected: PlantState) {
        let last = calendar.date(byAdding: .day, value: -days, to: today)!
        #expect(GrowthState.plantState(lastPostDate: last, today: today, calendar: calendar) == expected)
    }

    @Test("No record at all gives nil, not a dead plant")
    func noRecord() {
        #expect(GrowthState.plantState(lastPostDate: nil, today: today, calendar: calendar) == nil)
    }

    @Test("The time of day of the last note doesn't matter, only the calendar day")
    func timeOfDayIgnored() {
        let early = TestClock.date(2026, 10, 28, 0, 0)
        let late = TestClock.date(2026, 10, 28, 23, 59)
        #expect(GrowthState.plantState(lastPostDate: early, today: today, calendar: calendar) == .wilting)
        #expect(GrowthState.plantState(lastPostDate: late, today: today, calendar: calendar) == .wilting)
    }

    @Test("23:59 yesterday is still blooming at 00:00 today")
    func midnightBloomingEdge() {
        let last = TestClock.date(2026, 10, 29, 23, 59)
        let midnight = TestClock.date(2026, 10, 30, 0, 0)
        #expect(GrowthState.plantState(lastPostDate: last, today: midnight, calendar: calendar) == .blooming)
    }

    @Test("Crossing midnight tips a plant from blooming to wilting")
    func midnightTip() {
        let last = TestClock.date(2026, 10, 28, 23, 59)
        let beforeMidnight = TestClock.date(2026, 10, 29, 23, 59)
        let afterMidnight = TestClock.date(2026, 10, 30, 0, 0)
        #expect(GrowthState.plantState(lastPostDate: last, today: beforeMidnight, calendar: calendar) == .blooming)
        #expect(GrowthState.plantState(lastPostDate: last, today: afterMidnight, calendar: calendar) == .wilting)
    }

    @Test("A last post date in the future counts as blooming")
    func futureLastPost() {
        let future = TestClock.date(2026, 11, 2, 9, 0)
        #expect(GrowthState.plantState(lastPostDate: future, today: today, calendar: calendar) == .blooming)
    }

    @Test("The same two moments can fall in different states in different time zones")
    func timeZoneBoundary() {
        // 25 Oct 14:00 UTC is 26 Oct 01:00 in Sydney (UTC+11 in October).
        // 30 Oct 12:00 UTC is 30 Oct 23:00 in Sydney.
        let last = TestClock.date(2026, 10, 25, 14, 0)
        let now = TestClock.date(2026, 10, 30, 12, 0)
        let sydney = TestClock.calendar(timeZone: "Australia/Sydney")

        #expect(GrowthState.plantState(lastPostDate: last, today: now, calendar: TestClock.utc) == .dead)
        #expect(GrowthState.plantState(lastPostDate: last, today: now, calendar: sydney) == .wilting)
    }
}
