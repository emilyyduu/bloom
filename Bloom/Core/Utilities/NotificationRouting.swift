import Foundation
import UIKit
import UserNotifications
import SwiftData
import FirebaseAuth
import FirebaseFirestore

// The routing side of system notifications (the delegate itself is
// NotificationAppDelegate). Every friend notification is a system
// notification: posted locally by ActivityNotifier while Bloom is running,
// or delivered by the demo relay (xcrun simctl push) while it is closed.
// Taps on either come through here.

// The keys a delivered notification carries in userInfo. Plain strings,
// so it can cross from the notification centre's thread to the main actor.
struct NotificationPayload: Sendable {
    let type: String
    let noteOwnerUID: String?
    let noteID: String?
    let fromUID: String?
    let activityID: String?

    static let friendRequestTypes = ["request", "friendRequest", "friend_request"]

    // nil for anything without a "type", such as the daily reminder, so
    // tapping that just opens the app.
    init?(userInfo: [AnyHashable: Any]) {
        func string(_ key: String) -> String? {
            guard let value = userInfo[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        guard let type = string(NotificationConstants.Key.type) else { return nil }
        self.type = type
        typealias Key = NotificationConstants.Key
        noteOwnerUID = string(Key.noteOwnerUID)
        noteID = string(Key.noteID)
        fromUID = string(Key.fromUID)
        activityID = string(Key.activityID)
    }
}

// Turns a tapped banner into the same destination tapping that item in the
// feed would open (ActivityDestination), or the Notifications screen when
// that can't be done safely.
@MainActor
final class NotificationOpener {
    static let shared = NotificationOpener()
    private init() {}

    private var db: Firestore { Firestore.firestore() }

    func open(_ payload: NotificationPayload) async {
        guard let me = await signedInUID() else {
            // Signed out: nothing to show yet. The feed opens after sign in.
            ActivityRouter.shared.open(.feed)
            return
        }
        let destination = await destination(for: payload, me: me)
        // Signed out or switched account while looking it up.
        guard AuthService.shared.uid == me else { return }
        ActivityRouter.shared.open(destination)
    }

    // On a cold launch the saved sign in is restored a moment after the
    // app starts, so wait briefly for it before deciding I'm signed out.
    func signedInUID() async -> String? {
        for _ in 0..<20 {
            if let uid = AuthService.shared.uid { return uid }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return AuthService.shared.uid
    }

    private func destination(for payload: NotificationPayload, me: String) async -> ActivityDestination {
        // A friend request has no activity item, the feed lists requests.
        if NotificationPayload.friendRequestTypes.contains(payload.type) { return .feed }

        guard let kind = ActivityItem.Kind(rawValue: payload.type),
              await isForMe(payload, me: me),
              let destination = ActivityDestination(
                  kind: kind,
                  fromUID: payload.fromUID ?? "",
                  noteOwnerUID: payload.noteOwnerUID,
                  noteID: payload.noteID
              ) else { return .feed }

        if case .note(let ownerUID, let noteID, _) = destination,
           await !noteExists(ownerUID: ownerUID, noteID: noteID, me: me) {
            return .feed
        }
        return destination
    }

    // A notification meant for another account on this device has no
    // matching item in my feed.
    func isForMe(_ payload: NotificationPayload, me: String) async -> Bool {
        if let id = payload.activityID {
            if ActivityStore.shared.items.contains(where: { $0.id == id }) { return true }
            do {
                return try await db.collection("users").document(me).collection("activity").document(id)
                    .getDocument().exists
            } catch {
                // Offline: fall through to the weaker check below.
            }
        }
        return payload.fromUID != me
    }

    private func noteExists(ownerUID: String, noteID: String, me: String) async -> Bool {
        if ownerUID == me {
            guard let uuid = UUID(uuidString: noteID),
                  let container = try? StoreManager.shared.container(for: me) else { return false }
            var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == uuid })
            descriptor.fetchLimit = 1
            guard let note = try? container.mainContext.fetch(descriptor).first else { return false }
            return !note.isDraft
        }
        do {
            return try await db.collection("users").document(ownerUID).collection("notes").document(noteID)
                .getDocument().exists
        } catch {
            // Can't tell. Let the detail sheet say if it is gone.
            return true
        }
    }
}

// The app icon badge: requests waiting plus unread activity, zero while
// the notifications screen is open and after sign out.
@MainActor
final class NotificationBadge {
    static let shared = NotificationBadge()
    private init() {}

    private let center = UNUserNotificationCenter.current()
    private var unread = 0
    private var isFeedOpen = false
    private var lastTask: Task<Void, Never>?

    func update(unread: Int) {
        self.unread = unread
        apply()
    }

    // Reapplies the current value, for after permission is granted.
    func reapply() { apply() }

    func feedOpened() {
        isFeedOpen = true
        apply()
        Task { await removeDeliveredBanners() }
    }

    func feedClosed() {
        isFeedOpen = false
        apply()
    }

    // Sign out.
    func clear() {
        unread = 0
        isFeedOpen = false
        apply()
    }

    // Updates run one after another so an older value can't land last.
    private func apply() {
        let value = isFeedOpen ? 0 : unread
        let previous = lastTask
        lastTask = Task {
            await previous?.value
            try? await center.setBadgeCount(value)
        }
    }

    // Everything delivered except the daily reminder.
    private func removeDeliveredBanners() async {
        let delivered = await center.deliveredNotifications()
        let identifiers = delivered.map(\.request.identifier)
            .filter { !$0.hasPrefix(ReminderPlanner.identifierPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

