import Foundation

// Shared by every suite: a fixed Gregorian calendar in UTC, so no test
// depends on the device's time zone, locale or clock.
enum TestClock {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    static func calendar(timeZone identifier: String) -> Calendar {
        var calendar = utc
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
        calendar: Calendar = utc
    ) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return calendar.date(from: parts)!
    }

    static func startOfDay(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar = utc) -> Date {
        calendar.startOfDay(for: date(year, month, day, calendar: calendar))
    }
}
