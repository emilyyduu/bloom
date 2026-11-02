import Foundation

// The userInfo keys the notification code shares, in one place, so the
// delivered userInfo and the relay payload can't drift apart.
enum NotificationConstants {
    enum Key {
        static let type = "type"
        static let noteOwnerUID = "noteOwnerUID"
        static let noteID = "noteId"
        static let fromUID = "fromUID"
        static let activityID = "activityId"
    }
}
