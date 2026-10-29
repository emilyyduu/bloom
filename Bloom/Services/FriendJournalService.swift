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

    static let maxListeners = 20

    private let db = Firestore.firestore()

    @Published private(set) var latestNoteByFriend: [String: FriendNote] = [:]
    // A friend with nothing shared is .loaded with no note, which is not
    // the same as a load that hasn't finished or one that failed.
    @Published private(set) var loadStateByFriend: [String: LiveState] = [:]

    private var listeners: [String: ListenerRegistration] = [:]
    private var timeouts: [String: LiveTimeout] = [:]

    // Bumped on sign out so a fetch still in flight for the previous
    // account can't write its results into the next account's tiles.
    private var generation = 0

    func reset() {
        generation += 1
        stopAllListeners()
        latestNoteByFriend = [:]
        loadStateByFriend = [:]
    }

    func loadState(for uid: String) -> LiveState {
        loadStateByFriend[uid] ?? .loading
    }

    // MARK: Listeners

    // Makes the set of listeners match the friend list: new friends get
    // one, friends who left lose theirs and their tile data. Safe to call
    // as often as needed, a friend who already has a listener is skipped.
    // A friend whose listener ended in a final error state is left alone
    // until retry(uid).
    func syncListeners(for friendUIDs: [String]) {
        let wanted = Array(friendUIDs.prefix(Self.maxListeners))
        LiveLog.event("tile", "syncListeners wanted=\(wanted.count) have=\(listeners.count)", path: "users/*/notes", generation: generation)

        for uid in Array(listeners.keys) where !wanted.contains(uid) {
            detach(uid)
        }
        for uid in Array(latestNoteByFriend.keys) where !friendUIDs.contains(uid) {
            latestNoteByFriend[uid] = nil
        }
        for uid in Array(loadStateByFriend.keys) where !friendUIDs.contains(uid) {
            loadStateByFriend[uid] = nil
        }

        for uid in wanted where listeners[uid] == nil && (loadStateByFriend[uid].map { !$0.isFinal || $0 == .loaded } ?? true) {
            attach(to: uid)
        }
    }

    // Removes every listener and returns the tiles to a clean state:
    // a tile that had loaded keeps its note until the next first answer,
    // anything else goes back to loading so the next syncListeners
    // starts it again. Home calls this when it leaves the screen.
    func stopAllListeners() {
        LiveLog.event("tile", "stopAll (\(listeners.count) listeners)", path: "users/*/notes", generation: generation)
        for uid in Array(listeners.keys) { detach(uid) }
        for timeout in timeouts.values { timeout.cancel() }
        timeouts = [:]
        for (uid, state) in loadStateByFriend where state != .loaded {
            loadStateByFriend[uid] = .loading
        }
    }

    // The tile's Retry button: stops that friend's listener and starts a new one.
    func retry(_ uid: String) {
        detach(uid)
        attach(to: uid)
    }

    private func detach(_ uid: String) {
        listeners[uid]?.remove()
        listeners[uid] = nil
        timeouts[uid]?.cancel()
        timeouts[uid] = nil
    }

    private func attach(to uid: String) {
        guard listeners[uid] == nil else { return }
        let startedGeneration = generation
        let path = "users/\(uid)/notes (latest shared)"
        LiveLog.event("tile", "attach", path: path, generation: startedGeneration)
        // Whatever the tile already shows stays until the first answer.
        if loadStateByFriend[uid] != .loaded { loadStateByFriend[uid] = .loading }

        let timeout = LiveTimeout()
        timeouts[uid] = timeout
        timeout.start { [weak self] in
            guard let self, startedGeneration == self.generation, self.loadStateByFriend[uid] == .loading else { return }
            LiveLog.event("tile", "TIMED OUT after \(Int(LiveTimeout.seconds))s", path: path, generation: startedGeneration)
            self.detach(uid)
            self.loadStateByFriend[uid] = .failed
        }

        // includeMetadataChanges so the move from the cache to the server
        // is seen, otherwise a friend with nothing shared could never get
        // past an empty cache answer.
        listeners[uid] = latestNoteQuery(for: uid)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self, startedGeneration == self.generation, self.listeners[uid] != nil else {
                    LiveLog.event("tile", "callback DISCARDED (stale generation or removed)", path: path, generation: startedGeneration)
                    return
                }

                if let error {
                    LiveLog.error("tile", path: path, error: error, generation: startedGeneration)
                    // Firestore ends a listener that errored, so drop ours.
                    self.detach(uid)
                    self.loadStateByFriend[uid] = LiveState(error: error)
                    return
                }
                guard let snapshot else { return }

                LiveLog.snapshot("tile", path: path, count: snapshot.documents.count,
                                 fromCache: snapshot.metadata.isFromCache, generation: startedGeneration)

                // An empty answer from the cache only means nothing is
                // cached yet. Wait for the server (or the timeout) before
                // saying nothing is shared.
                if snapshot.documents.isEmpty, snapshot.metadata.isFromCache, self.loadStateByFriend[uid] != .loaded {
                    return
                }

                self.timeouts[uid]?.cancel()
                self.latestNoteByFriend[uid] = snapshot.decoded(as: FriendNote.self).first
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

        for uid in friendUIDs.prefix(Self.maxListeners) where loadStateByFriend[uid].map({ $0.isFinal && $0 != .loaded }) ?? false {
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
                loadStateByFriend[uid] = LiveState(error: error)
                #if DEBUG
                logFriendNotesError(error, while: "fetching \(uid)'s latest shared note")
                #endif
            }
        }
    }
}

// One friend's shared journal: their notes with sharedWithFriends ==
// true, newest first, the most recent 500. Owned per screen rather than as
// a singleton, so nothing is shared between friends: start() resets
// every property, and the listener lives only between FriendJournalView's
// onAppear and onDisappear. Months and counts come from what is loaded,
// hitLimit says there may be older notes that were not.
@MainActor
final class FriendJournalListener: ObservableObject {
    enum LoadState {
        case loading
        case loaded
        case permissionDenied
        // Any other error, most often a missing composite index.
        case failed
    }

    static let limit = 500

    @Published private(set) var notes: [FriendNote] = []
    @Published private(set) var state: LoadState = .loading
    @Published private(set) var hitLimit = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var friendUID: String?

    func start(friendUID: String) {
        stop()
        self.friendUID = friendUID
        notes = []
        state = .loading
        hitLimit = false

        // DEBUG sample friends are never looked up in Firestore.
        #if DEBUG
        if friendUID.hasPrefix("sample-") {
            notes = SampleCircleData.journalNotes(for: friendUID)
            state = .loaded
            return
        }
        #endif
        attach()
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    private func attach() {
        guard let friendUID else { return }
        listener?.remove()

        listener = db.collection("users").document(friendUID).collection("notes")
            .whereField("sharedWithFriends", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: Self.limit)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, self.friendUID == friendUID else { return }

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
                self.hitLimit = (snapshot?.documents.count ?? 0) >= Self.limit
                self.state = .loaded

                #if DEBUG
                let documentCount = snapshot?.documents.count ?? 0
                print("FriendJournalListener: \(friendUID) returned \(documentCount) document(s) " +
                    "(limit \(Self.limit)), \(fetched.count) decoded, " +
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
