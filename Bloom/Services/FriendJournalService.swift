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
    // A voice memo exists at users/{friendUID}/audio/{id} when hasAudio
    // is true. Optional so notes without the fields still decode. The
    // bytes are only fetched when someone taps play.
    var hasAudio: Bool?
    var audioSeconds: Int?
}

// The single most recent note each accepted friend has shared, for Home's
// friend tiles. One live snapshot listener per friend (at most 20), so a
// newly shared or unshared note shows up on its own. The listeners live
// only while Home is on screen: Home calls syncListeners(for:) when it
// appears and when the friend list changes, and stopAllListeners() when
// it disappears. refreshLatestNotes(for:) is a safety net for when the
// app becomes active and for pull to refresh, never the only way in.
@MainActor
final class FriendJournalService: ObservableObject {
    static let shared = FriendJournalService()
    private init() {}

    // What a tile knows about a friend's latest note. A friend with
    // nothing shared is .loaded with no note, which is not the same as
    // a load that hasn't finished or one that failed.
    enum TileLoadState {
        case loading
        case loaded
        case failed
    }

    static let maxListeners = 20

    private let db = Firestore.firestore()

    @Published private(set) var latestNoteByFriend: [String: FriendNote] = [:]
    @Published private(set) var loadStateByFriend: [String: TileLoadState] = [:]

    private var listeners: [String: ListenerRegistration] = [:]

    // Bumped on sign out so a fetch still in flight for the previous
    // account can't write its results into the next account's tiles.
    private var generation = 0

    func reset() {
        generation += 1
        stopAllListeners()
        latestNoteByFriend = [:]
        loadStateByFriend = [:]
    }

    func loadState(for uid: String) -> TileLoadState {
        loadStateByFriend[uid] ?? .loading
    }

    // MARK: Listeners

    // Makes the set of listeners match the friend list: new friends get
    // one, friends who left lose theirs and their tile data. Safe to call
    // as often as needed, a friend who already has a listener is skipped.
    // A friend whose listener failed is left alone until retry(uid).
    func syncListeners(for friendUIDs: [String]) {
        let wanted = Array(friendUIDs.prefix(Self.maxListeners))

        for uid in Array(listeners.keys) where !wanted.contains(uid) {
            listeners[uid]?.remove()
            listeners[uid] = nil
        }
        for uid in Array(latestNoteByFriend.keys) where !friendUIDs.contains(uid) {
            latestNoteByFriend[uid] = nil
        }
        for uid in Array(loadStateByFriend.keys) where !friendUIDs.contains(uid) {
            loadStateByFriend[uid] = nil
        }

        for uid in wanted where listeners[uid] == nil && loadStateByFriend[uid] != .failed {
            attach(to: uid)
        }
    }

    func stopAllListeners() {
        for listener in listeners.values { listener.remove() }
        listeners = [:]
    }

    // The tile's Retry button.
    func retry(_ uid: String) {
        guard listeners[uid] == nil else { return }
        attach(to: uid)
    }

    private func attach(to uid: String) {
        guard listeners[uid] == nil else { return }
        let startedGeneration = generation
        // Whatever the tile already shows stays until the first answer.
        if loadStateByFriend[uid] != .loaded { loadStateByFriend[uid] = .loading }

        // includeMetadataChanges so the move from the cache to the server
        // is seen, otherwise a friend with nothing shared could never get
        // past an empty cache answer.
        listeners[uid] = latestNoteQuery(for: uid)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self, startedGeneration == self.generation, self.listeners[uid] != nil else { return }

                if let error {
                    // Firestore ends a listener that errored, so drop ours.
                    self.listeners[uid]?.remove()
                    self.listeners[uid] = nil
                    self.loadStateByFriend[uid] = .failed
                    #if DEBUG
                    logFriendNotesError(error, while: "listening to \(uid)'s latest shared note")
                    #endif
                    return
                }
                guard let snapshot else { return }

                let notes = snapshot.decoded(as: FriendNote.self)
                #if DEBUG
                print("FriendJournalService: tile listener fired for \(uid), \(snapshot.documents.count) document(s), " +
                    "fromCache \(snapshot.metadata.isFromCache), at \(Date().formatted(date: .omitted, time: .standard))")
                #endif

                // An empty answer from the cache only means nothing is
                // cached yet. Wait for the server before saying nothing
                // is shared.
                if snapshot.documents.isEmpty, snapshot.metadata.isFromCache, self.loadStateByFriend[uid] != .loaded {
                    return
                }

                self.latestNoteByFriend[uid] = notes.first
                self.loadStateByFriend[uid] = .loaded
            }
    }

    private func latestNoteQuery(for uid: String) -> Query {
        db.collection("users").document(uid).collection("notes")
            .whereField("sharedWithFriends", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
    }

    // MARK: Safety net

    // For when the app becomes active and for pull to refresh. Listeners
    // keep the tiles current on their own, so this only re-attaches the
    // ones that failed, and fetches once for friends past the cap, who
    // have no listener.
    func refreshLatestNotes(for friendUIDs: [String]) async {
        let startedGeneration = generation

        for uid in friendUIDs.prefix(Self.maxListeners) where loadStateByFriend[uid] == .failed {
            retry(uid)
        }

        for uid in friendUIDs.dropFirst(Self.maxListeners) {
            do {
                let snapshot = try await latestNoteQuery(for: uid).getDocuments()
                guard startedGeneration == generation else { return }
                latestNoteByFriend[uid] = snapshot.decoded(as: FriendNote.self).first
                loadStateByFriend[uid] = .loaded
            } catch {
                guard startedGeneration == generation else { return }
                loadStateByFriend[uid] = .failed
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
