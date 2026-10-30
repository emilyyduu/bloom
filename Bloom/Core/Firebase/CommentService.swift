import Foundation
import Combine
import FirebaseFirestore

// One comment on a shared note, stored at
// users/{ownerUID}/notes/{noteId}/comments/{commentId} with exactly
// authorUID, text and createdAt, plus replyToUID and replyToCommentId
// when it is a reply. Comments never touch SwiftData.
struct NoteComment: Identifiable, Equatable {
    static let maxLength = 500

    let id: String
    let authorUID: String
    let text: String
    let createdAt: Date
    // The person replied to, and the top level comment the reply hangs
    // under (one level of threading). Both nil for a top level comment.
    var replyToUID: String? = nil
    var replyToCommentId: String? = nil

    var isReply: Bool { replyToCommentId != nil }
}

// Who a reply is addressed to. threadID is always the top level comment,
// toUID is the author of the comment that was tapped. mention is the
// "@username " text put into the field (empty if the username is unknown).
struct CommentReplyTarget: Equatable {
    let threadID: String
    let toUID: String
    let toName: String
    let mention: String
}

// A top level comment with its replies, oldest first. A reply whose
// parent was deleted is shown as a top level comment with parentDeleted.
struct CommentThread: Identifiable {
    let top: NoteComment
    let parentDeleted: Bool
    let replies: [NoteComment]

    var id: String { top.id }

    static func threads(from comments: [NoteComment]) -> [CommentThread] {
        let sorted = comments.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        let byID = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // The comment a reply belongs under, or nil when it stands alone
        // (not a reply, parent deleted, or a malformed chain).
        func threadID(for comment: NoteComment) -> String? {
            guard var current = comment.replyToCommentId, byID[current] != nil, current != comment.id else { return nil }
            var hops = 0
            while let next = byID[current]?.replyToCommentId, byID[next] != nil, hops < 5 {
                current = next
                hops += 1
            }
            // Only a comment that is itself top level can hold replies.
            guard let parent = byID[current], !isChild(parent) else { return nil }
            return current
        }
        func isChild(_ comment: NoteComment) -> Bool {
            guard let parentID = comment.replyToCommentId else { return false }
            return byID[parentID] != nil
        }

        var repliesByThread: [String: [NoteComment]] = [:]
        var tops: [NoteComment] = []
        for comment in sorted {
            if let id = threadID(for: comment) {
                repliesByThread[id, default: []].append(comment)
            } else {
                tops.append(comment)
            }
        }
        return tops.map { top in
            let deleted = top.replyToCommentId.map { byID[$0] == nil } ?? false
            return CommentThread(top: top, parentDeleted: deleted, replies: repliesByThread[top.id] ?? [])
        }
    }
}

// The live comments of one note, owned per sheet so nothing is shared
// between notes. One listener ordered by createdAt ascending and
// nothing else, so no composite index is needed. Attached on appear and
// removed on disappear.
@MainActor
final class NoteCommentsListener: ObservableObject {
    @Published private(set) var comments: [NoteComment] = []
    @Published private(set) var state: LiveState = .loading

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var ownerUID: String?
    private var noteID: String?
    private let timeout = LiveTimeout()

    private var collection: CollectionReference? {
        guard let ownerUID, let noteID else { return nil }
        return db.collection("users").document(ownerUID).collection("notes").document(noteID).collection("comments")
    }

    // For one off writes with no listener, such as a notification action:
    // points send() at a note without attaching anything.
    func prepareForOneOffWrite(ownerUID: String, noteID: String) {
        self.ownerUID = ownerUID
        self.noteID = noteID
    }

    // Starting the note that is already running does nothing.
    func start(ownerUID: String, noteID: String) {
        if listener != nil, self.ownerUID == ownerUID, self.noteID == noteID { return }
        stop()
        self.ownerUID = ownerUID
        self.noteID = noteID

        timeout.start { [weak self] in
            guard let self, self.state == .loading else { return }
            self.listener?.remove()
            self.listener = nil
            self.state = .failed
        }

        listener = collection?
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, self.noteID == noteID, self.ownerUID == ownerUID else { return }
                self.timeout.cancel()

                if let error {
                    self.listener?.remove()
                    self.listener = nil
                    self.state = LiveState(error: error)
                    return
                }
                guard let snapshot else { return }

                self.comments = snapshot.documents.compactMap(Self.comment(from:))
                self.state = .loaded
                CommentCounts.shared.set(self.comments.count, ownerUID: ownerUID, noteID: noteID)
            }
    }

    // The Retry button: a new listener for the same note.
    func retry() {
        guard let ownerUID, let noteID else { return }
        stop()
        start(ownerUID: ownerUID, noteID: noteID)
    }

    // Always leaves a clean state, so presenting the sheet again starts
    // a fresh listener from loading.
    func stop() {
        listener?.remove()
        listener = nil
        timeout.cancel()
        comments = []
        state = .loading
    }

    private static func comment(from document: QueryDocumentSnapshot) -> NoteComment? {
        let data = document.data()
        guard let authorUID = data["authorUID"] as? String,
              let text = data["text"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else { return nil }
        return NoteComment(
            id: document.documentID,
            authorUID: authorUID,
            text: text,
            createdAt: createdAt,
            replyToUID: data["replyToUID"] as? String,
            replyToCommentId: data["replyToCommentId"] as? String
        )
    }

    // Writes the comment, or a reply when replyTo is set. The listener
    // shows it straight away from the local cache, a thrown error means
    // the write was refused.
    func send(_ text: String, authorUID: String, replyTo: CommentReplyTarget? = nil) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= NoteComment.maxLength else { return }

        guard let collection else { return }
        let commentRef = collection.document()
        var data: [String: Any] = [
            "authorUID": authorUID,
            "text": trimmed,
            "createdAt": Timestamp(date: Date()),
        ]
        if let replyTo {
            data["replyToUID"] = replyTo.toUID
            data["replyToCommentId"] = replyTo.threadID
        }
        try await commentRef.setData(data)

        let commentID = commentRef.documentID
        if let replyTo {
            // A reply tells the person replied to, and only them, unless
            // that is me. Best effort.
            if let ownerUID, let noteID, replyTo.toUID != authorUID {
                Task {
                    await ActivityWriter.replied(
                        commentID: commentID, authorUID: authorUID, toUID: replyTo.toUID,
                        noteOwnerUID: ownerUID, noteID: noteID, text: trimmed
                    )
                }
            }
        } else if let ownerUID, let noteID, ownerUID != authorUID {
            // Tell the note's owner, unless it's my own note. Best effort.
            Task {
                await ActivityWriter.commented(
                    commentID: commentID, authorUID: authorUID, noteOwnerUID: ownerUID, noteID: noteID, text: trimmed
                )
            }
        }
    }

    func delete(_ comment: NoteComment) async throws {
        try await collection?.document(comment.id).delete()
    }
}

// How many comments a card shows, loaded lazily with a count
// aggregate when the card appears and cached for the session. A failed
// count is simply absent, so no number is shown.
@MainActor
final class CommentCounts: ObservableObject {
    static let shared = CommentCounts()
    private init() {}

    @Published private(set) var counts: [String: Int] = [:]
    private var inFlight: Set<String> = []

    static func key(ownerUID: String, noteID: String) -> String { "\(ownerUID)/\(noteID)" }

    func count(ownerUID: String?, noteID: String?) -> Int? {
        guard let ownerUID, let noteID else { return nil }
        return counts[Self.key(ownerUID: ownerUID, noteID: noteID)]
    }

    func ensure(ownerUID: String?, noteID: String?) async {
        guard let ownerUID, let noteID else { return }
        let key = Self.key(ownerUID: ownerUID, noteID: noteID)
        guard counts[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        let query = Firestore.firestore().collection("users").document(ownerUID)
            .collection("notes").document(noteID).collection("comments").count
        guard let snapshot = try? await query.getAggregation(source: .server) else { return }
        counts[key] = snapshot.count.intValue
    }

    func set(_ count: Int, ownerUID: String, noteID: String) {
        counts[Self.key(ownerUID: ownerUID, noteID: noteID)] = count
    }

    func reset() {
        counts = [:]
        inFlight = []
    }
}

// Names and pictures for comment authors, looked up once per uid. An
// author doesn't have to be my friend, so this reads the users
// document directly rather than FriendService's list.
actor UserProfileCache {
    static let shared = UserProfileCache()

    private var profiles: [String: FirestoreUser] = [:]

    func profile(uid: String) async -> FirestoreUser? {
        if let cached = profiles[uid] { return cached }

        do {
            let snapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
            guard let user = try? snapshot.data(as: FirestoreUser.self) else { return nil }
            profiles[uid] = user
            return user
        } catch {
            return nil
        }
    }

    func reset() { profiles = [:] }
}
