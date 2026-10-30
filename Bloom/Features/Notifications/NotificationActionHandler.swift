import Foundation
import SwiftData
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

// What the buttons on a notification do. Each one does its work for real,
// with the app possibly launched in the background just for this, and is
// awaited before the delegate returns. Nothing happens when no account is
// signed in or the notification was scheduled for a different account.
@MainActor
enum NotificationActionHandler {
    private typealias A = NotificationConstants.Action

    private struct ActionError: Error { let message: String }

    static func perform(action: String, text: String?, payload: NotificationPayload?, recipientUID: String?) async {
        guard let me = await NotificationOpener.shared.signedInUID() else { return }
        if let recipientUID, recipientUID != me { return }

        switch action {
        case A.accept, A.decline:
            await respondToRequest(accept: action == A.accept, payload: payload, me: me)
        case A.reply, A.comment:
            await sendComment(isReply: action == A.reply, text: text, payload: payload, me: me)
        case A.love:
            await sendLove(payload: payload, me: me)
        case A.quickNote:
            await saveQuickNote(text: text, me: me)
        case A.snooze:
            await snooze(me: me)
        default:
            break
        }
    }

    // MARK: - Friend request

    private static func respondToRequest(accept: Bool, payload: NotificationPayload?, me: String) async {
        guard let fromUID = payload?.fromUID else { return }
        do {
            try await withDeadline {
                // The request is read first. One that is gone, already
                // answered or addressed to someone else is simply ignored.
                let snapshot = try await Firestore.firestore().collection("friendships")
                    .document("\(fromUID)_\(me)").getDocument()
                guard snapshot.exists,
                      let friendship = try? snapshot.data(as: Friendship.self),
                      friendship.toUID == me, friendship.status == .pending else { return }
                if accept {
                    try await FriendService.shared.acceptFriendRequest(friendship)
                } else {
                    try await FriendService.shared.declineRequest(friendship)
                }
            }
        } catch {
            await fail(accept ? "accept the request" : "decline the request", error)
        }
    }

    // MARK: - Comment or reply

    private static func sendComment(isReply: Bool, text: String?, payload: NotificationPayload?, me: String) async {
        guard let payload, let ownerUID = payload.noteOwnerUID, let noteID = payload.noteID,
              await NotificationOpener.shared.isForMe(payload, me: me) else { return }
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let noun = isReply ? "reply" : "comment"

        do {
            try await withDeadline {
                var body = trimmed
                var replyTo: CommentReplyTarget?

                // A reply is addressed to whoever wrote the comment, with
                // their @username in front, and hangs under that comment.
                if isReply, let fromUID = payload.fromUID {
                    let profile = await UserProfileCache.shared.profile(uid: fromUID)
                    let mention = profile.map { "@\($0.username) " } ?? ""
                    body = mention + trimmed
                    if let commentID = payload.commentID ?? commentID(fromActivityID: payload.activityID) {
                        replyTo = CommentReplyTarget(
                            threadID: commentID, toUID: fromUID,
                            toName: profile?.shownName ?? "Someone", mention: mention
                        )
                    }
                }
                guard body.count <= NoteComment.maxLength else { throw ActionError(message: "too long") }

                let comments = NoteCommentsListener()
                comments.prepareForOneOffWrite(ownerUID: ownerUID, noteID: noteID)
                try await comments.send(body, authorUID: me, replyTo: replyTo)
            }
        } catch {
            await fail("send your \(noun)", error)
        }
    }

    // The activity id of a comment is comment_<id> (reply_<id> for a reply).
    private static func commentID(fromActivityID id: String?) -> String? {
        guard let id else { return nil }
        for prefix in ["comment_", "reply_"] where id.hasPrefix(prefix) {
            return String(id.dropFirst(prefix.count))
        }
        return nil
    }

    // MARK: - Love

    private static func sendLove(payload: NotificationPayload?, me: String) async {
        guard let payload, let ownerUID = payload.noteOwnerUID, let noteID = payload.noteID,
              await NotificationOpener.shared.isForMe(payload, me: me) else { return }
        do {
            try await withDeadline {
                // With nothing loaded, toggle always sets, never removes.
                let reactions = NoteReactionsListener()
                reactions.prepareForOneOffWrite(ownerUID: ownerUID, noteID: noteID)
                await reactions.toggle(.love, myUID: me)
                if reactions.errorMessage != nil { throw ActionError(message: "reaction refused") }
            }
        } catch {
            await fail("send your reaction", error)
        }
    }

    // MARK: - Quick note

    // Posted straight into today's journal, the same way the composer
    // posts, in the signed in account's own store.
    private static func saveQuickNote(text: String?, me: String) async {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let context: ModelContext
        let note: Note
        do {
            context = try StoreManager.shared.container(for: me).mainContext
            note = Note.createDraft(in: context, text: trimmed)
            note.isDraft = false
            note.createdAt = Date()
            note.journal = Journal.journal(for: note.createdAt, in: context)
            note.ownerUID = me
            note.sharedWithFriends = AccountDefaults.shareNewNotes
            note.syncedAt = nil
            try context.save()
        } catch {
            await fail("save your note", error)
            return
        }

        NotificationScheduler.shared.cancelTodaysReminder()

        // The note is safe on the device now. If these can't finish, the
        // upload is retried by syncPending and the streak on the next launch.
        do {
            try await withDeadline { try await NoteSyncService.shared.uploadAndWait(note) }
        } catch {
        }
        try? await withDeadline { await StreakSyncService.shared.sync(context: context) }
    }

    // MARK: - Snooze

    private static func snooze(me: String) async {
        let content = UNMutableNotificationContent()
        content.title = NotificationScheduler.title
        content.body = NotificationScheduler.body
        content.sound = .default
        content.categoryIdentifier = NotificationConstants.Category.reminder
        content.userInfo = [NotificationConstants.Key.recipientUID: me]
        let request = UNNotificationRequest(
            identifier: NotificationConstants.snoozeIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            await fail("set your reminder", error)
        }
    }

    // MARK: - Helpers

    // Firestore writes wait for the network, which can be forever on a
    // phone with no signal. Gives up after 20 seconds so the failure can be
    // reported while the app is still allowed to run. A write that timed
    // out stays queued and goes through when the connection returns.
    private static func withDeadline(_ body: @escaping @MainActor () async throws -> Void) async throws {
        final class Gate { var isOpen = true }
        let gate = Gate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                do {
                    try await body()
                    if gate.isOpen { gate.isOpen = false; continuation.resume() }
                } catch {
                    if gate.isOpen { gate.isOpen = false; continuation.resume(throwing: error) }
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                if gate.isOpen { gate.isOpen = false; continuation.resume(throwing: ActionError(message: "timed out")) }
            }
        }
    }

    // A local notification, since the person may have the app closed.
    private static func fail(_ what: String, _ error: Error) async {
        let content = UNMutableNotificationContent()
        content.title = NotificationScheduler.title
        content.body = "Couldn\u{2019}t \(what). Open Bloom to try again."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "bloom.actionfailed.\(UUID().uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
