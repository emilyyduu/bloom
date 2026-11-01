import Foundation
import Testing
@testable import Bloom

@MainActor
@Suite("Reminder planning")
struct ReminderPlannerTests {
    let calendar = TestClock.utc
    let today = TestClock.startOfDay(2026, 10, 30)

    private func logged(_ values: [(Int, Int, Int)]) -> Set<Date> {
        Set(values.map { TestClock.startOfDay($0.0, $0.1, $0.2) })
    }

    // MARK: Which days get a reminder

    @Test("With nothing logged, the next 7 days each get one reminder")
    func sevenDays() {
        let plan = ReminderPlanner.reminderDays(from: today, loggedDates: [], calendar: calendar)
        #expect(plan.count == 7)
        #expect(plan.first?.date == today)
        #expect(plan.last?.date == TestClock.startOfDay(2026, 11, 5))
    }

    @Test("Days that already have a note are skipped")
    func loggedDaysSkipped() {
        let plan = ReminderPlanner.reminderDays(
            from: today, loggedDates: logged([(2026, 10, 30), (2026, 11, 2)]), calendar: calendar
        )
        #expect(plan.count == 5)
        #expect(!plan.contains { $0.date == today })
        #expect(!plan.contains { $0.date == TestClock.startOfDay(2026, 11, 2) })
    }

    @Test("A note logged outside the 7 day window changes nothing")
    func outsideWindowIgnored() {
        let plan = ReminderPlanner.reminderDays(
            from: today, loggedDates: logged([(2026, 10, 29), (2026, 11, 6)]), calendar: calendar
        )
        #expect(plan.count == 7)
    }

    @Test("When every day is logged there is nothing to plan")
    func allLogged() {
        let all = Set((0..<7).map { calendar.date(byAdding: .day, value: $0, to: today)! })
        #expect(ReminderPlanner.reminderDays(from: today, loggedDates: all, calendar: calendar).isEmpty)
    }

    @Test("Each day gets exactly one reminder with its own identifier")
    func oneReminderPerDay() {
        let plan = ReminderPlanner.reminderDays(from: today, loggedDates: [], calendar: calendar)
        #expect(Set(plan.map(\.identifier)).count == plan.count)
        #expect(Set(plan.map(\.date)).count == plan.count)
    }

    @Test("Identifiers use the prefix and a year-month-day, across a month and year end")
    func identifiers() {
        #expect(ReminderPlanner.identifier(for: today, calendar: calendar) == "bloom.reminder.2026-10-30")
        #expect(
            ReminderPlanner.identifier(for: TestClock.startOfDay(2026, 12, 31), calendar: calendar)
                == "bloom.reminder.2026-12-31"
        )
        #expect(
            ReminderPlanner.identifier(for: TestClock.startOfDay(2027, 1, 1), calendar: calendar)
                == "bloom.reminder.2027-01-01"
        )
    }

    // MARK: Habit time (median of recent notes)

    @Test("Fewer than the minimum number of notes gives no habit time")
    func habitNeedsMinimum() {
        let now = TestClock.date(2026, 10, 30, 12, 0)
        let notes = (1...(ReminderPlanner.habitMinimumNotes - 1)).map { TestClock.date(2026, 10, 30 - $0, 20, 0) }
        #expect(ReminderPlanner.habitMinutes(noteDates: notes, now: now, calendar: calendar) == nil)
        #expect(ReminderPlanner.habitMinutes(noteDates: [], now: now, calendar: calendar) == nil)
    }

    @Test("The habit time is the median of the notes' times of day")
    func habitMedianOdd() throws {
        let now = TestClock.date(2026, 10, 30, 12, 0)
        let notes = [
            TestClock.date(2026, 10, 27, 8, 0),
            TestClock.date(2026, 10, 28, 20, 0),
            TestClock.date(2026, 10, 29, 21, 0),
        ]
        // Sorted: 08:00, 20:00, 21:00. The middle one is 20:00.
        #expect(ReminderPlanner.habitMinutes(noteDates: notes, now: now, calendar: calendar) == 20 * 60)
    }

    @Test("With an even number of notes the two middle times are averaged")
    func habitMedianEven() {
        let now = TestClock.date(2026, 10, 30, 12, 0)
        let notes = [8, 9, 10, 11].enumerated().map { TestClock.date(2026, 10, 20 + $0.offset, $0.element, 0) }
        #expect(ReminderPlanner.habitMinutes(noteDates: notes, now: now, calendar: calendar) == 9 * 60 + 30)
    }

    @Test("The habit time rounds to the nearest 5 minutes", arguments: [
        (12, 1210), (13, 1215), (17, 1215), (18, 1220),
    ])
    func habitRounding(minute: Int, expected: Int) {
        let now = TestClock.date(2026, 10, 30, 12, 0)
        let notes = (1...3).map { TestClock.date(2026, 10, 30 - $0, 20, minute) }
        #expect(ReminderPlanner.habitMinutes(noteDates: notes, now: now, calendar: calendar) == expected)
    }

    @Test("A habit time never goes past 23:59")
    func habitCapped() {
        let now = TestClock.date(2026, 10, 30, 12, 0)
        let notes = (1...3).map { TestClock.date(2026, 10, 30 - $0, 23, 59) }
        #expect(ReminderPlanner.habitMinutes(noteDates: notes, now: now, calendar: calendar) == 24 * 60 - 1)
    }

    @Test("Only notes from the last 30 days count, and none from the future")
    func habitWindow() {
        let now = TestClock.date(2026, 10, 30, 12, 0)
        // 30 days before is 30 September 12:00. That moment is inside, a minute before is not.
        let inside = TestClock.date(2026, 9, 30, 12, 0)
        let justOutside = TestClock.date(2026, 9, 30, 11, 59)
        let future = TestClock.date(2026, 10, 31, 8, 0)

        let onlyOneInWindow = [inside, justOutside, future, TestClock.date(2026, 8, 1, 8, 0)]
        #expect(ReminderPlanner.habitMinutes(noteDates: onlyOneInWindow, now: now, calendar: calendar) == nil)

        let withSecond = onlyOneInWindow + [TestClock.date(2026, 10, 29, 12, 0)]
        // Two notes are in the window, still under the minimum of 3.
        #expect(ReminderPlanner.habitMinutes(noteDates: withSecond, now: now, calendar: calendar) == nil)

        let withThird = withSecond + [TestClock.date(2026, 10, 28, 12, 0)]
        #expect(ReminderPlanner.habitMinutes(noteDates: withThird, now: now, calendar: calendar) == 12 * 60)
    }

    // MARK: Effective time

    @Test("The chosen time is used when not adapting to habits")
    func effectiveFixed() {
        let settings = ReminderSettings(isEnabled: true, minutes: 18 * 60, adaptsToHabits: false)
        let now = TestClock.date(2026, 10, 30, 12, 0)
        let notes = (1...5).map { TestClock.date(2026, 10, 30 - $0, 9, 0) }
        #expect(ReminderPlanner.effectiveMinutes(settings, noteDates: notes, now: now, calendar: calendar) == 18 * 60)
    }

    @Test("The chosen time is the fallback when adapting but there is no habit yet")
    func effectiveFallback() {
        let settings = ReminderSettings(isEnabled: true, minutes: 18 * 60, adaptsToHabits: true)
        let now = TestClock.date(2026, 10, 30, 12, 0)
        #expect(ReminderPlanner.effectiveMinutes(settings, noteDates: [], now: now, calendar: calendar) == 18 * 60)
    }

    @Test("The habit time is used when adapting and there is one")
    func effectiveHabit() {
        let settings = ReminderSettings(isEnabled: true, minutes: 18 * 60, adaptsToHabits: true)
        let now = TestClock.date(2026, 10, 30, 12, 0)
        let notes = (1...5).map { TestClock.date(2026, 10, 30 - $0, 9, 0) }
        #expect(ReminderPlanner.effectiveMinutes(settings, noteDates: notes, now: now, calendar: calendar) == 9 * 60)
    }

    // MARK: Fire date and next reminder

    @Test("A reminder fires at the chosen minutes after midnight on that day")
    func fireDate() {
        let fire = ReminderPlanner.fireDate(on: today, minutes: 21 * 60 + 30, calendar: calendar)
        #expect(fire == TestClock.date(2026, 10, 30, 21, 30))
    }

    @Test("The next reminder is today's when its time hasn't passed")
    func nextToday() {
        let now = TestClock.date(2026, 10, 30, 10, 0)
        let next = ReminderPlanner.nextReminder(loggedDates: [], minutes: 18 * 60, now: now, calendar: calendar)
        #expect(next == TestClock.date(2026, 10, 30, 18, 0))
    }

    @Test("The next reminder is tomorrow's when today's time has passed")
    func nextTomorrow() {
        let now = TestClock.date(2026, 10, 30, 19, 0)
        let next = ReminderPlanner.nextReminder(loggedDates: [], minutes: 18 * 60, now: now, calendar: calendar)
        #expect(next == TestClock.date(2026, 10, 31, 18, 0))
    }

    @Test("Logging today moves the next reminder to tomorrow")
    func nextSkipsLoggedToday() {
        let now = TestClock.date(2026, 10, 30, 10, 0)
        let next = ReminderPlanner.nextReminder(
            loggedDates: logged([(2026, 10, 30)]), minutes: 18 * 60, now: now, calendar: calendar
        )
        #expect(next == TestClock.date(2026, 10, 31, 18, 0))
    }

    @Test("There is no next reminder when the whole week is logged")
    func nextNone() {
        let now = TestClock.date(2026, 10, 30, 10, 0)
        let all = Set((0..<7).map { calendar.date(byAdding: .day, value: $0, to: today)! })
        #expect(ReminderPlanner.nextReminder(loggedDates: all, minutes: 18 * 60, now: now, calendar: calendar) == nil)
    }
}
