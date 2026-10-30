import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// One thing that happened that concerns me: a friend shared a note,
// someone commented on a note of mine, or a request I sent was
// accepted. Stored at users/{me}/activity/{activityId} with exactly
// type, fromUID, createdAt and, optionally, noteOwnerUID, noteId and
// preview (at most 120 characters). Never in SwiftData.
struct ActivityItem: Identifiable, Equatable {
    enum Kind: String {
        case note
        case comment
        case reaction
        case accepted
    }

    static let previewLimit = 120

    let id: String
    let kind: Kind
    let fromUID: String
    let createdAt: Date
    let noteOwnerUID: String?
    let noteID: String?
    let preview: String?

    // Skips a document that doesn't decode instead of crashing, like
    // ChatChannel.init?(document:) in the messaging lab.
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let typeString = data["type"] as? String,
              let kind = Kind(rawValue: typeString),
              let fromUID = data["fromUID"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else { return nil }

        self.id = document.documentID
        self.kind = kind
        self.fromUID = fromUID
        self.createdAt = createdAt
        self.noteOwnerUID = data["noteOwnerUID"] as? String
        self.noteID = data["noteId"] as? String
        self.preview = data["preview"] as? String
    }
}

// Whoever causes an event writes it into the recipient's activity.
// Best effort: silent in release, printed in DEBUG, and never a reason
// for the real action to fail. Sample friends are never written to.
enum ActivityWriter {
    private static var db: Firestore { Firestore.firestore() }

    private static func data(
        kind: ActivityItem.Kind,
        fromUID: String,
        noteOwnerUID: String? = nil,
        noteID: String? = nil,
        preview: String? = nil
    ) -> [String: Any] {
        var data: [String: Any] = [
            "type": kind.rawValue,
            "fromUID": fromUID,
            "createdAt": Timestamp(date: Date()),
        ]
        if let noteOwnerUID { data["noteOwnerUID"] = noteOwnerUID }
        if let noteID { data["noteId"] = noteID }
        if let preview {
            let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
            // Cut by whole characters so an emoji is never split.
            if !trimmed.isEmpty { data["preview"] = String(trimmed.prefix(ActivityItem.previewLimit)) }
        }
        return data
    }

    // A note I posted and shared, to each accepted friend (at most 30).
    // The id is fixed so a retry can't duplicate it.
    static func noteShared(noteID: String, ownerUID: String, text: String, friendUIDs: [String]) async {
        let recipients = friendUIDs.filter { !$0.hasPrefix("sample-") }.prefix(30)
        guard !recipients.isEmpty else { return }

        let batch = db.batch()
        for friendUID in recipients {
            let ref = db.collection("users").document(friendUID).collection("activity").document("note_\(noteID)")
            batch.setData(
                data(kind: .note, fromUID: ownerUID, noteOwnerUID: ownerUID, noteID: noteID, preview: text),
                forDocument: ref
            )
        }
        do {
            try await batch.commit()
            AccountDefaults.markNotifiedFriends(aboutNote: noteID)
        } catch {
            log(error, "telling friends about note \(noteID)")
        }
    }

    // My comment on someone else's note, to the note's owner.
    static func commented(commentID: String, authorUID: String, noteOwnerUID: String, noteID: String, text: String) async {
        guard authorUID != noteOwnerUID, !noteOwnerUID.hasPrefix("sample-") else { return }
        do {
            try await db.collection("users").document(noteOwnerUID).collection("activity")
                .document("comment_\(commentID)")
                .setData(data(kind: .comment, fromUID: authorUID, noteOwnerUID: noteOwnerUID, noteID: noteID, preview: text))
        } catch {
            log(error, "telling \(noteOwnerUID) about my comment")
        }
    }

    // My reply to someone's comment, to that person. Type comment, preview
    // "replied: " then the start of my text. Refused by the rules when
    // they aren't my friend, which is fine.
    static func replied(commentID: String, authorUID: String, toUID: String, noteOwnerUID: String, noteID: String, text: String) async {
        guard authorUID != toUID, !toUID.hasPrefix("sample-") else { return }
        do {
            try await db.collection("users").document(toUID).collection("activity")
                .document("reply_\(commentID)")
                .setData(data(kind: .comment, fromUID: authorUID, noteOwnerUID: noteOwnerUID, noteID: noteID, preview: "replied: \(text)"))
        } catch {
            log(error, "telling \(toUID) about my reply")
        }
    }

    // My reaction on someone else's note, to the note's owner. The id is
    // fixed per note and reactor, so changing my reaction overwrites it.
    static func reacted(noteID: String, reactorUID: String, noteOwnerUID: String) async {
        guard reactorUID != noteOwnerUID, !noteOwnerUID.hasPrefix("sample-") else { return }
        do {
            try await db.collection("users").document(noteOwnerUID).collection("activity")
                .document("reaction_\(noteID)_\(reactorUID)")
                .setData(data(kind: .reaction, fromUID: reactorUID, noteOwnerUID: noteOwnerUID, noteID: noteID))
        } catch {
            log(error, "telling \(noteOwnerUID) about my reaction")
        }
    }

    // A request I accepted, to the person who sent it.
    static func accepted(myUID: String, requesterUID: String) async {
        guard !requesterUID.hasPrefix("sample-") else { return }
        do {
            try await db.collection("users").document(requesterUID).collection("activity")
                .document("accepted_\(myUID)")
                .setData(data(kind: .accepted, fromUID: myUID))
        } catch {
            log(error, "telling \(requesterUID) that I accepted")
        }
    }

    private static func log(_ error: Error, _ action: String) {
        #if DEBUG
        logFirestoreError(error, while: "\(action). Permission denied here means the activity rules aren't published")
        #endif
    }
}

// The live feed: one listener on users/{me}/activity ordered by
// createdAt, newest first, limited to 50. Per account, started when the
// signed in UI appears and removed in the account reset on sign out.
@MainActor
final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()
    private init() {}

    @Published private(set) var items: [ActivityItem] = []
    @Published private(set) var isLoading = true
    @Published private(set) var state: LiveState = .loading
    @Published var errorMessage: String?
    @Published private(set) var lastSeen = Date()

    private var listener: ListenerRegistration?
    private var hasReceivedFirstSnapshot = false
    private let timeout = LiveTimeout()

    var unreadCount: Int {
        items.filter { $0.createdAt > lastSeen }.count
    }

    // Safe to call more than once, it only attaches once.
    func startListening() {
        guard listener == nil, let myUID = Auth.auth().currentUser?.uid else {
            LiveLog.event("activity", "start SKIPPED (listener exists: \(listener != nil))", path: "users/?/activity")
            return
        }
        LiveLog.event("activity", "start", path: "users/\(myUID)/activity")
        lastSeen = AccountDefaults.activityLastSeen
        isLoading = true
        state = .loading
        errorMessage = nil
        hasReceivedFirstSnapshot = false

        timeout.start { [weak self] in
            guard let self, self.state == .loading else { return }
            LiveLog.event("activity", "TIMED OUT after \(Int(LiveTimeout.seconds))s", path: "users/\(myUID)/activity")
            self.listener?.remove()
            self.listener = nil
            self.fail(.failed)
        }

        listener = Firestore.firestore().collection("users").document(myUID).collection("activity")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                self.timeout.cancel()
                self.isLoading = false
                if let error { LiveLog.error("activity", path: "users/\(myUID)/activity", error: error) }
                else if let snapshot { LiveLog.snapshot("activity", path: "users/\(myUID)/activity", count: snapshot.documents.count, fromCache: snapshot.metadata.isFromCache) }

                if let error {
                    // Firestore ends a listener that errored.
                    self.listener?.remove()
                    self.listener = nil
                    self.fail(LiveState(error: error))
                    return
                }
                guard let snapshot else { return }
                self.state = .loaded
                self.errorMessage = nil
                self.items = snapshot.documents.compactMap(ActivityItem.init(document:))

                // Only items that arrive after the first snapshot are
                // new. What was already there at launch is not.
                if self.hasReceivedFirstSnapshot {
                    for change in snapshot.documentChanges where change.type == .added {
                        guard let item = ActivityItem(document: change.document) else { continue }
                        self.arrived(item)
                    }
                }
                self.hasReceivedFirstSnapshot = true
            }
    }

    private func fail(_ newState: LiveState) {
        isLoading = false
        state = newState
        errorMessage = newState == .permissionDenied
            ? "You can\u{2019}t see your notifications"
            : "Couldn\u{2019}t load your notifications"
    }

    // The Retry button: stops the listener and starts a new one.
    func retry() {
        stopListening()
        startListening()
    }

    func stopListening() {
        timeout.cancel()
        state = .loading
        LiveLog.event("activity", "stop", path: "users/?/activity")
        listener?.remove()
        listener = nil
        items = []
        isLoading = true
        errorMessage = nil
        hasReceivedFirstSnapshot = false
    }

    // Opening the notifications screen.
    func markAllSeen() {
        let now = Date()
        lastSeen = now
        AccountDefaults.activityLastSeen = now
    }

    private func arrived(_ item: ActivityItem) {
        // An old item the server delivered late isn't news. Neither is my
        // own action, or anything while the list that shows it is open.
        guard item.createdAt > lastSeen, Date().timeIntervalSince(item.createdAt) < 600,
              item.fromUID != Auth.auth().currentUser?.uid,
              !ActivityRouter.shared.isFeedOpen else { return }
        Task { await ActivityNotifier.post(for: item) }
    }
}

// Where tapping an item or a system notification goes.
enum ActivityDestination: Identifiable {
    case feed
    case note(ownerUID: String, noteID: String, focusComments: Bool)
    case friend(uid: String)

    var id: String {
        switch self {
        case .feed: return "feed"
        case .note(let ownerUID, let noteID, _): return "note-\(ownerUID)-\(noteID)"
        case .friend(let uid): return "friend-\(uid)"
        }
    }

    init?(item: ActivityItem) {
        self.init(kind: item.kind, fromUID: item.fromUID, noteOwnerUID: item.noteOwnerUID, noteID: item.noteID)
    }

    // Shared with tapped system notifications, which carry the same fields.
    init?(kind: ActivityItem.Kind, fromUID: String, noteOwnerUID: String?, noteID: String?) {
        switch kind {
        case .accepted:
            guard !fromUID.isEmpty else { return nil }
            self = .friend(uid: fromUID)
        case .note, .comment, .reaction:
            guard let noteOwnerUID, let noteID else { return nil }
            self = .note(ownerUID: noteOwnerUID, noteID: noteID, focusComments: kind == .comment)
        }
    }
}

// Presents a destination from the signed in UI, for notification taps.
@MainActor
final class ActivityRouter: ObservableObject {
    static let shared = ActivityRouter()
    private init() {}

    @Published var destination: ActivityDestination?
    // True while the notifications screen is on screen, where a system
    // notification would only repeat what the list shows.
    var isFeedOpen = false

    // False until the signed in UI (ContentView) is on screen, so a tapped
    // system banner on a cold launch waits for somewhere to present.
    private var isReady = false
    private var pending: (destination: ActivityDestination, date: Date)?

    // From a tapped system banner. Held for up to 5 minutes if the signed
    // in UI isn't up yet (a cold launch, or signed out until sign in).
    func open(_ destination: ActivityDestination) {
        if isReady {
            self.destination = destination
        } else {
            pending = (destination, Date())
        }
    }

    func markReady() {
        isReady = true
        guard let pending else { return }
        self.pending = nil
        if Date().timeIntervalSince(pending.date) < 300 { destination = pending.destination }
    }

    func reset() {
        destination = nil
        isFeedOpen = false
        isReady = false
        pending = nil
    }
}
