import Foundation

// How healthy a plant in the Shared Circle Garden looks, based purely
// on how long it's been since that person last logged a note.
enum PlantState: Equatable {
    case blooming
    case wilting
    case dead
}

enum GrowthState {
    // `lastPostDate` is nil when there's no streak record at all yet
    // (a brand new friend, say), which shows as an empty plot rather
    // than a dead one. Kept as a pure function, independent of
    // Firestore or SceneKit, so it's easy to test with fixed dates.
    static func plantState(lastPostDate: Date?, today: Date, calendar: Calendar = .current) -> PlantState? {
        guard let lastPostDate else { return nil }

        let lastDay = calendar.startOfDay(for: lastPostDate)
        let todayDay = calendar.startOfDay(for: today)
        let daysSince = calendar.dateComponents([.day], from: lastDay, to: todayDay).day ?? 0

        switch daysSince {
        case ...1:
            return .blooming
        case 2...4:
            return .wilting
        default:
            return .dead
        }
    }
}
