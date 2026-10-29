#if DEBUG
import Foundation
import UserNotifications
import FirebaseAuth

// Local stand-ins for the relay, to try every category and action without
// it. Each schedules a notification 5 seconds out with the category and
// userInfo a real one carries, so Bloom must be sent to the background
// before it fires. Settings > Debug.
enum DebugBanner {
    enum Kind: String, CaseIterable {
        case friendRequest = "friend request"
        case comment
        case note
        case reminder
    }

    // activityIds that start with this skip the "is it in my feed" check.
    static let activityPrefix = "debug_"

    // Returns the message to show under the buttons.
    @MainActor
    static func schedule(_ kind: Kind, latestNoteID: String?) async -> String {
        guard let me = Auth.auth().currentUser?.uid else { return "Sign in first." }
        await NotificationManager.shared.refresh()
        guard NotificationManager.shared.canScheduleNotifications else { return "Allow phone alerts first." }

        typealias Key = NotificationConstants.Key
        let content = UNMutableNotificationContent()
        content.sound = .default
        // A friend if I have one, otherwise me, so a reply or reaction has
        // someone to be addressed to.
        let fromUID = FriendService.shared.friends.first?.id ?? me
        let activityID = "\(activityPrefix)\(UUID().uuidString)"

        switch kind {
        case .friendRequest:
            // Accept and Decline act on a real pending request.
            guard let request = FriendService.shared.pendingIncoming.first else {
                return "No pending friend request to test with. Send one from another account."
            }
            content.title = "Bloom"
            content.body = "A friend sent you a friend request"
            content.categoryIdentifier = NotificationConstants.Category.friendRequest
            content.userInfo = [Key.type: "friendRequest", Key.fromUID: request.fromUID, Key.recipientUID: me]
        case .comment:
            guard let latestNoteID else { return "Post a note first." }
            content.title = "Bloom"
            content.body = "A friend commented: Love this!"
            content.categoryIdentifier = NotificationConstants.Category.comment
            content.userInfo = [
                Key.type: "comment", Key.noteOwnerUID: me, Key.noteID: latestNoteID, Key.fromUID: fromUID,
                Key.activityID: activityID, Key.commentID: "\(activityPrefix)comment", Key.recipientUID: me,
            ]
        case .note:
            guard let latestNoteID else { return "Post a note first." }
            content.title = "Bloom"
            content.body = "A friend shared a note"
            content.categoryIdentifier = NotificationConstants.Category.note
            content.userInfo = [
                Key.type: "note", Key.noteOwnerUID: me, Key.noteID: latestNoteID, Key.fromUID: fromUID,
                Key.activityID: activityID, Key.recipientUID: me,
            ]
        case .reminder:
            content.title = NotificationScheduler.title
            content.body = NotificationScheduler.body
            content.categoryIdentifier = NotificationConstants.Category.reminder
            content.userInfo = [Key.recipientUID: me]
        }

        let request = UNNotificationRequest(
            identifier: "bloom.debug.\(kind.rawValue.replacingOccurrences(of: " ", with: ""))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            return "Scheduled. Send Bloom to the background now."
        } catch {
            return error.localizedDescription
        }
    }
}
#endif
