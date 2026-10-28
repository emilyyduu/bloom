import Foundation
import FirebaseFirestore

// A friend's shared note, decoded from users/{friendUID}/notes.
// Sharing is text only, there's no photo field to decode.
struct FriendNote: Codable, Identifiable {
    @DocumentID var id: String?
    var text: String
    var createdAt: Date
}

// Fetches, per accepted friend, the single most recent note they've
// shared, for Home's friend tiles. A plain fetch rather than a live
// listener since a tile preview only needs to be refreshed when Home
// appears or the app returns to the foreground, not instantly.
@MainActor
final class FriendJournalService: ObservableObject {
    static let shared = FriendJournalService()
    private init() {}

    private let db = Firestore.firestore()

    @Published private(set) var latestNoteByFriend: [String: FriendNote] = [:]

    func refreshLatestNotes(for friendUIDs: [String]) async {
        for uid in friendUIDs {
            do {
                let snapshot = try await db.collection("users").document(uid).collection("notes")
                    .whereField("sharedWithFriends", isEqualTo: true)
                    .order(by: "createdAt", descending: true)
                    .limit(to: 1)
                    .getDocuments()
                latestNoteByFriend[uid] = snapshot.decoded(as: FriendNote.self).first
            } catch {
                #if DEBUG
                logFriendNotesError(error, while: "fetching \(uid)'s latest shared note")
                #endif
            }
        }
    }
}

// A friend's full shared journal: every note of theirs with
// sharedWithFriends == true, newest first. Owned per screen rather
// than as a singleton, its listener's lifecycle is tied to one
// FriendJournalView's onAppear and onDisappear.
@MainActor
final class FriendJournalListener: ObservableObject {
    @Published private(set) var notes: [FriendNote] = []
    @Published private(set) var isPermissionDenied = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func start(friendUID: String) {
        stop()
        listener = db.collection("users").document(friendUID).collection("notes")
            .whereField("sharedWithFriends", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    let nsError = error as NSError
                    self.isPermissionDenied = nsError.domain == FirestoreErrorDomain
                        && nsError.code == FirestoreErrorCode.permissionDenied.rawValue
                    #if DEBUG
                    logFriendNotesError(error, while: "listening to \(friendUID)'s shared notes")
                    #endif
                    return
                }
                self.isPermissionDenied = false
                self.notes = snapshot?.decoded(as: FriendNote.self) ?? []
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }
}

#if DEBUG
// This query (sharedWithFriends ascending, createdAt descending)
// needs a composite index. A failed precondition error here means
// that index doesn't exist yet in Firestore, surface it rather than
// restructuring the query to avoid needing one.
private func logFriendNotesError(_ error: Error, while action: String) {
    let nsError = error as NSError
    if nsError.domain == FirestoreErrorDomain, nsError.code == FirestoreErrorCode.failedPrecondition.rawValue {
        print("FriendJournalService: \(action) needs a composite index on " +
            "(sharedWithFriends ascending, createdAt descending). Create it in the Firebase console: \(error)")
    } else {
        logFirestoreError(error, while: action)
    }
}
#endif
