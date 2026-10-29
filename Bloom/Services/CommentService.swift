import Foundation
import Combine
import FirebaseFirestore

// One comment on a shared note, stored at
// users/{ownerUID}/notes/{noteId}/comments/{commentId} with exactly
// authorUID, text and createdAt. Comments never touch SwiftData.
struct NoteComment: Identifiable, Equatable {
    static let maxLength = 500

    let id: String
    let authorUID: String
    let text: String
    let createdAt: Date
}

// The live comments of one note, owned per sheet so nothing is shared
// between notes. One listener ordered by createdAt ascending and
// nothing else, so no composite index is needed. Attached on appear and
// removed on disappear.
@MainActor
final class NoteCommentsListener: ObservableObject {
    enum LoadState {
        case loading
        case loaded
        case permissionDenied
        case failed
    }

    @Published private(set) var comments: [NoteComment] = []
    @Published private(set) var state: LoadState = .loading

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var ownerUID: String?
    private var noteID: String?

    private var isSample: Bool { ownerUID?.hasPrefix("sample-") ?? false }

    private var collection: CollectionReference? {
        guard let ownerUID, let noteID else { return nil }
        return db.collection("users").document(ownerUID).collection("notes").document(noteID).collection("comments")
    }

    func start(ownerUID: String, noteID: String) {
        stop()
        self.ownerUID = ownerUID
        self.noteID = noteID
        comments = []
        state = .loading

        // DEBUG sample friends never touch Firestore.
        guard !ownerUID.hasPrefix("sample-") else {
            #if DEBUG
            comments = Self.sampleComments
            state = .loaded
            #endif
            return
        }

        listener = collection?
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, self.noteID == noteID else { return }

                if let error {
                    let nsError = error as NSError
                    let isDenied = nsError.domain == FirestoreErrorDomain
                        && nsError.code == FirestoreErrorCode.permissionDenied.rawValue
                    self.state = isDenied ? .permissionDenied : .failed
                    #if DEBUG
                    logFirestoreError(error, while: "listening to comments on \(noteID)")
                    #endif
                    return
                }

                self.comments = (snapshot?.documents ?? []).compactMap(Self.comment(from:))
                self.state = .loaded
                CommentCounts.shared.set(self.comments.count, ownerUID: ownerUID, noteID: noteID)
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    private static func comment(from document: QueryDocumentSnapshot) -> NoteComment? {
        let data = document.data()
        guard let authorUID = data["authorUID"] as? String,
              let text = data["text"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else { return nil }
        return NoteComment(id: document.documentID, authorUID: authorUID, text: text, createdAt: createdAt)
    }

    // Writes the comment. The listener shows it straight away from the
    // local cache, a thrown error means the write was refused.
    func send(_ text: String, authorUID: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= NoteComment.maxLength else { return }

        if isSample {
            comments.append(NoteComment(id: UUID().uuidString, authorUID: authorUID, text: trimmed, createdAt: Date()))
            return
        }
        guard let collection else { return }
        let commentRef = collection.document()
        do {
            try await commentRef.setData([
                "authorUID": authorUID,
                "text": trimmed,
                "createdAt": Timestamp(date: Date()),
            ])
        } catch {
            #if DEBUG
            logFirestoreError(error, while: "sending a comment. Permission denied here means the comments rules aren't published")
            #endif
            throw error
        }

        // Tell the note's owner, unless it's my own note. Best effort.
        if let ownerUID, let noteID, ownerUID != authorUID {
            let commentID = commentRef.documentID
            Task {
                await ActivityWriter.commented(
                    commentID: commentID, authorUID: authorUID, noteOwnerUID: ownerUID, noteID: noteID, text: trimmed
                )
            }
        }
    }

    func delete(_ comment: NoteComment) async throws {
        if isSample {
            comments.removeAll { $0.id == comment.id }
            return
        }
        do {
            try await collection?.document(comment.id).delete()
        } catch {
            #if DEBUG
            logFirestoreError(error, while: "deleting comment \(comment.id)")
            #endif
            throw error
        }
    }

    #if DEBUG
    private static let sampleComments: [NoteComment] = [
        NoteComment(id: "sample-comment-1", authorUID: "sample-priya", text: "Love this one.", createdAt: Date().addingTimeInterval(-7200)),
        NoteComment(id: "sample-comment-2", authorUID: "sample-tom", text: "Same, we should go again soon.", createdAt: Date().addingTimeInterval(-3600)),
    ]
    #endif
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
        guard let ownerUID, let noteID, !ownerUID.hasPrefix("sample-") else { return }
        let key = Self.key(ownerUID: ownerUID, noteID: noteID)
        guard counts[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        do {
            let query = Firestore.firestore().collection("users").document(ownerUID)
                .collection("notes").document(noteID).collection("comments").count
            let snapshot = try await query.getAggregation(source: .server)
            counts[key] = snapshot.count.intValue
        } catch {
            #if DEBUG
            logFirestoreError(error, while: "counting comments on \(noteID)")
            #endif
        }
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
        guard !uid.hasPrefix("sample-") else { return Self.sampleProfile(uid) }

        do {
            let snapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
            guard let user = try? snapshot.data(as: FirestoreUser.self) else { return nil }
            profiles[uid] = user
            return user
        } catch {
            #if DEBUG
            logFirestoreError(error, while: "loading the profile of \(uid)")
            #endif
            return nil
        }
    }

    func reset() { profiles = [:] }

    private static func sampleProfile(_ uid: String) -> FirestoreUser {
        let name = uid.replacingOccurrences(of: "sample-", with: "").capitalized
        return FirestoreUser(id: uid, username: name.lowercased(), displayName: name, createdAt: Date())
    }
}
