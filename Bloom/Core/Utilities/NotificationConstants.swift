import Foundation
import UserNotifications

// Every identifier the notification code shares, in one place, so the
// categories, the actions, the delivered userInfo and the relay payload
// can't drift apart.
enum NotificationConstants {
    enum Category {
        static let friendRequest = "bloom.friendRequest"
        static let comment = "bloom.comment"
        static let note = "bloom.note"
        static let reminder = "bloom.reminder"
    }

    enum Action {
        static let accept = "bloom.action.accept"
        static let decline = "bloom.action.decline"
        static let reply = "bloom.action.reply"
        static let comment = "bloom.action.comment"
        static let love = "bloom.action.love"
        static let quickNote = "bloom.action.quickNote"
        static let snooze = "bloom.action.snooze"
    }

    enum Key {
        static let type = "type"
        static let noteOwnerUID = "noteOwnerUID"
        static let noteID = "noteId"
        static let fromUID = "fromUID"
        static let activityID = "activityId"
        static let commentID = "commentId"
        // Which account a notification was scheduled for. Set on the
        // reminders. The relay may add it too.
        static let recipientUID = "recipientUID"
    }

    // A one off reminder from "Remind me in 1 hour". Deliberately not
    // under "bloom.reminder." so refreshing the 7 day window keeps it.
    static let snoozeIdentifier = "bloom.snooze"
}

// All categories are registered here, once, at launch.
enum NotificationCategories {
    typealias A = NotificationConstants.Action

    static func register() {
        let accept = UNNotificationAction(identifier: A.accept, title: "Accept", options: [.authenticationRequired])
        let decline = UNNotificationAction(identifier: A.decline, title: "Decline", options: [.destructive, .authenticationRequired])
        let friendRequest = UNNotificationCategory(
            identifier: NotificationConstants.Category.friendRequest,
            actions: [accept, decline],
            intentIdentifiers: []
        )

        let reply = UNTextInputNotificationAction(
            identifier: A.reply,
            title: "Reply",
            options: [.authenticationRequired],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Write a reply"
        )
        let comment = UNNotificationCategory(
            identifier: NotificationConstants.Category.comment,
            actions: [reply],
            intentIdentifiers: []
        )

        let love = UNNotificationAction(identifier: A.love, title: "Love", options: [.authenticationRequired])
        let commentOnNote = UNTextInputNotificationAction(
            identifier: A.comment,
            title: "Comment",
            options: [.authenticationRequired],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Write a comment"
        )
        let note = UNNotificationCategory(
            identifier: NotificationConstants.Category.note,
            actions: [love, commentOnNote],
            intentIdentifiers: []
        )

        let quickNote = UNTextInputNotificationAction(
            identifier: A.quickNote,
            title: "Quick note",
            options: [.authenticationRequired],
            textInputButtonTitle: "Save",
            textInputPlaceholder: "What\u{2019}s on your mind?"
        )
        let snooze = UNNotificationAction(identifier: A.snooze, title: "Remind me in 1 hour", options: [])
        let reminder = UNNotificationCategory(
            identifier: NotificationConstants.Category.reminder,
            actions: [quickNote, snooze],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([friendRequest, comment, note, reminder])
    }
}
