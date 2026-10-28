import Foundation
import FirebaseFirestore
import Combine

// A friend's shared note, decoded from users/{friendUID}/notes.
// hasPhoto says whether a photo document exists at
// users/{friendUID}/photos/{id}, the bytes themselves are only
// fetched on demand by FriendPhotoCache. It defaults to false so
// older documents without the field still decode.
struct FriendNote: Codable, Identifiable {
    @DocumentID var id: String?
    var text: String
    var createdAt: Date
    var hasPhoto: Bool = false
    // Only set on a note the friend has pinned, nil otherwise and on
    // older documents. Used to order a friend's pinned notes.
    var pinnedAt: Date?
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

    // Bumped on sign out so a fetch still in flight for the previous
    // account can't write its results into the next account's tiles.
    private var generation = 0

    func reset() {
        generation += 1
        latestNoteByFriend = [:]
    }

    func refreshLatestNotes(for friendUIDs: [String]) async {
        let startedGeneration = generation
        for uid in friendUIDs {
            do {
                let snapshot = try await db.collection("users").document(uid).collection("notes")
                    .whereField("sharedWithFriends", isEqualTo: true)
                    .order(by: "createdAt", descending: true)
                    .limit(to: 1)
                    .getDocuments()
                guard startedGeneration == generation else { return }
                latestNoteByFriend[uid] = snapshot.decoded(as: FriendNote.self).first
            } catch {
                #if DEBUG
                logFriendNotesError(error, while: "fetching \(uid)'s latest shared note")
                #endif
            }
        }
    }
}

// One friend's shared journal: their notes with sharedWithFriends ==
// true, newest first, the most recent 100 to start with and 100 more
// each time loadEarlier() is called. Owned per screen rather than as
// a singleton, so nothing is shared between friends: start() resets
// every property, and the listener lives only between FriendJournalView's
// onAppear and onDisappear.
@MainActor
final class FriendJournalListener: ObservableObject {
    enum LoadState {
        case loading
        case loaded
        case permissionDenied
        // Any other error, most often a missing composite index.
        case failed
    }

    static let pageSize = 100

    @Published private(set) var notes: [FriendNote] = []
    @Published private(set) var state: LoadState = .loading
    @Published private(set) var canLoadMore = false
    @Published private(set) var isLoadingMore = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var friendUID: String?
    private var limit = FriendJournalListener.pageSize

    func start(friendUID: String) {
        stop()
        self.friendUID = friendUID
        limit = Self.pageSize
        notes = []
        state = .loading
        canLoadMore = false
        isLoadingMore = false
        attach()
    }

    // Raises the limit by a page and re-attaches, so the same listener
    // keeps delivering live updates while reaching further back.
    func loadEarlier() {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        limit += Self.pageSize
        attach()
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    private func attach() {
        guard let friendUID else { return }
        listener?.remove()

        let requestedLimit = limit
        listener = db.collection("users").document(friendUID).collection("notes")
            .whereField("sharedWithFriends", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: requestedLimit)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, self.friendUID == friendUID else { return }
                self.isLoadingMore = false

                if let error {
                    let nsError = error as NSError
                    let isDenied = nsError.domain == FirestoreErrorDomain
                        && nsError.code == FirestoreErrorCode.permissionDenied.rawValue
                    self.state = isDenied ? .permissionDenied : .failed
                    #if DEBUG
                    logFriendNotesError(error, while: "listening to \(friendUID)'s shared notes")
                    #endif
                    return
                }

                let fetched = snapshot?.decoded(as: FriendNote.self) ?? []
                self.notes = fetched
                self.canLoadMore = (snapshot?.documents.count ?? 0) >= requestedLimit
                self.state = .loaded

                #if DEBUG
                let documentCount = snapshot?.documents.count ?? 0
                print("FriendJournalListener: \(friendUID) returned \(documentCount) document(s) " +
                    "(limit \(requestedLimit)), \(fetched.count) decoded, " +
                    "\(fetched.filter(\.hasPhoto).count) with a photo. " +
                    "Query: users/\(friendUID)/notes where sharedWithFriends == true, createdAt descending, " +
                    "so every document counted here has sharedWithFriends true.")
                if documentCount != fetched.count {
                    print("FriendJournalListener: \(documentCount - fetched.count) document(s) failed to decode")
                }
                #endif
            }
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
