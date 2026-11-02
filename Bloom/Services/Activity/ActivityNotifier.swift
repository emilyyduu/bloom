import Foundation
import UserNotifications
import FirebaseAuth

// Turns a genuinely new piece of friend activity into a system
// notification, right away (a 1 second trigger, the shortest a local
// notification allows). Called by ActivityStore for a new activity item and
// by FriendService for a new incoming request. Nothing is posted for my own
// actions, with the type's toggle off, or without permission.
@MainActor
enum ActivityNotifier {
    private typealias Key = NotificationConstants.Key

    static func post(for item: ActivityItem) async {
        let base: String
        switch item.kind {
        case .note: base = AccountDefaults.notifyFriendNotesBase
        case .comment: base = AccountDefaults.notifyCommentsBase
        case .reaction: base = AccountDefaults.notifyReactionsBase
        case .accepted: base = AccountDefaults.notifyFriendRequestsBase
        }
        guard let me = Auth.auth().currentUser?.uid, item.fromUID != me,
              !BlockService.shared.isBlocked(item.fromUID),
              AccountDefaults.isNotificationEnabled(base) else { return }
        let name = await UserProfileCache.shared.profile(uid: item.fromUID)?.shownName ?? "Someone"

        let body: String
        switch item.kind {
        case .note:
            body = "\(name) shared a note"
        case .comment:
            if let preview = item.preview, preview.hasPrefix("replied: ") {
                body = "\(name) \(preview)"
            } else if let preview = item.preview, !preview.isEmpty {
                body = "\(name) commented: \(preview)"
            } else {
                body = "\(name) commented"
            }
        case .reaction:
            body = "\(name) reacted to your note"
        case .accepted:
            body = "\(name) accepted your friend request"
        }

        var userInfo: [String: String] = [
            Key.type: item.kind.rawValue,
            Key.fromUID: item.fromUID,
            Key.activityID: item.id,
        ]
        if let noteOwnerUID = item.noteOwnerUID { userInfo[Key.noteOwnerUID] = noteOwnerUID }
        if let noteID = item.noteID { userInfo[Key.noteID] = noteID }

        await add(
            identifier: "activity_\(item.id)",
            body: body,
            thread: "bloom.activity.\(item.kind.rawValue)",
            userInfo: userInfo,
            me: me
        )
    }

    static func postRequest(from uid: String) async {
        guard let me = Auth.auth().currentUser?.uid, !uid.isEmpty, uid != me,
              AccountDefaults.isNotificationEnabled(AccountDefaults.notifyFriendRequestsBase) else { return }
        let name = await UserProfileCache.shared.profile(uid: uid)?.shownName ?? "Someone"
        await add(
            identifier: "request_\(uid)",
            body: "\(name) sent you a friend request",
            thread: "bloom.friendRequest",
            userInfo: [Key.type: "friendRequest", Key.fromUID: uid],
            me: me
        )
    }

    // Same identifier replaces the earlier one, so a repeat never stacks.
    private static func add(
        identifier: String,
        body: String,
        thread: String,
        userInfo: [String: String],
        me: String
    ) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: break
        default: return
        }
        // Signed out or switched account while the name loaded.
        guard Auth.auth().currentUser?.uid == me else { return }

        let content = UNMutableNotificationContent()
        content.title = "Bloom"
        content.body = body
        content.sound = .default
        content.threadIdentifier = thread
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await center.add(request)
    }
}
