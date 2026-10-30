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

// "Today" for what friends can see of each other's notes: the viewer's
// current calendar day, from the start of today up to the start of
// tomorrow. Computed fresh each time so it follows the device clock.
struct FriendDay: Equatable {
    let start: Date
    let end: Date

    init(containing date: Date = Date(), calendar: Calendar = .current) {
        start = calendar.startOfDay(for: date)
        end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    func contains(_ date: Date) -> Bool { date >= start && date < end }

    // The one query every "shared today" screen uses: it reuses the
    // composite index (sharedWithFriends ascending, createdAt descending).
    func sharedNotesQuery(friendUID: String, db: Firestore = Firestore.firestore()) -> Query {
        db.collection("users").document(friendUID).collection("notes")
            .whereField("sharedWithFriends", isEqualTo: true)
            .whereField("createdAt", isGreaterThanOrEqualTo: Timestamp(date: start))
            .whereField("createdAt", isLessThan: Timestamp(date: end))
            .order(by: "createdAt", descending: true)
    }
}

// The single most recent note each accepted friend has shared today, for
// Home's friend tiles. One live snapshot listener per friend (at most 20),
// so a newly shared or unshared note shows up on its own. The listeners
// live only while Home is on screen: Home calls syncListeners(for:) when it
// appears, when the friend list changes and when the day changes, and
// stopAllListeners() when it disappears. refreshLatestNotes(for:) is a
// safety net for when the app becomes active and for pull to refresh,
// never the only way in.
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

    // The day the current listeners were attached for. When the calendar
    // day moves on, syncListeners drops them and starts again.
    private var attachedDay: FriendDay?

    // Bumped on sign out so a fetch still in flight for the previous
    // account can't write its results into the next account's tiles.
    private var generation = 0

    func reset() {
        generation += 1
        stopAllListeners()
        latestNoteByFriend = [:]
        loadStateByFriend = [:]
        attachedDay = nil
    }

    func loadState(for uid: String) -> LiveState {
        loadStateByFriend[uid] ?? .loading
    }

    // MARK: Listeners

    // Makes the set of listeners match the friend list: new friends get
    // one, friends who left lose theirs and their tile data. Safe to call
    // as often as needed, a friend who already has a listener is skipped.
    // A friend whose listener ended in a final error state is left alone
    // until retry(uid). If the calendar day changed since the listeners
    // were attached, everything restarts for the new day.
    func syncListeners(for friendUIDs: [String]) {
        rolloverIfNeeded()

        let wanted = Array(friendUIDs.prefix(Self.maxListeners))

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

    // A new day means yesterday's tile notes are no longer visible: drop
    // the listeners and the data so the tiles show loading, then the next
    // attach asks for the new day.
    private func rolloverIfNeeded() {
        let today = FriendDay()
        defer { attachedDay = today }
        guard let attachedDay, attachedDay != today else { return }
        for uid in Array(listeners.keys) { detach(uid) }
        latestNoteByFriend = [:]
        loadStateByFriend = [:]
    }

    // Removes every listener and returns the tiles to a clean state:
    // a tile that had loaded keeps its note until the next first answer,
    // anything else goes back to loading so the next syncListeners
    // starts it again. Home calls this when it leaves the screen.
    func stopAllListeners() {
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
        let day = FriendDay()
        // Whatever the tile already shows stays until the first answer.
        if loadStateByFriend[uid] != .loaded { loadStateByFriend[uid] = .loading }

        let timeout = LiveTimeout()
        timeouts[uid] = timeout
        timeout.start { [weak self] in
            guard let self, startedGeneration == self.generation, self.loadStateByFriend[uid] == .loading else { return }
            self.detach(uid)
            self.loadStateByFriend[uid] = .failed
        }

        // includeMetadataChanges so the move from the cache to the server
        // is seen, otherwise a friend with nothing shared could never get
        // past an empty cache answer.
        listeners[uid] = latestNoteQuery(for: uid, day: day)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self, startedGeneration == self.generation, self.listeners[uid] != nil else { return }

                if let error {
                    // Firestore ends a listener that errored, so drop ours.
                    self.detach(uid)
                    self.loadStateByFriend[uid] = LiveState(error: error)
                    return
                }
                guard let snapshot else { return }

                // An empty answer from the cache only means nothing is
                // cached yet. Wait for the server (or the timeout) before
                // saying nothing is shared.
                if snapshot.documents.isEmpty, snapshot.metadata.isFromCache, self.loadStateByFriend[uid] != .loaded {
                    return
                }

                self.timeouts[uid]?.cancel()
                self.latestNoteByFriend[uid] = snapshot.decoded(as: FriendNote.self).first { day.contains($0.createdAt) }
                self.loadStateByFriend[uid] = .loaded
            }
    }

    // Today only, newest first, one note.
    private func latestNoteQuery(for uid: String, day: FriendDay = FriendDay()) -> Query {
        day.sharedNotesQuery(friendUID: uid, db: db).limit(to: 1)
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
                let day = FriendDay()
                let snapshot = try await latestNoteQuery(for: uid, day: day).getDocuments()
                guard startedGeneration == generation else { return }
                latestNoteByFriend[uid] = snapshot.decoded(as: FriendNote.self).first { day.contains($0.createdAt) }
                loadStateByFriend[uid] = .loaded
            } catch {
                guard startedGeneration == generation else { return }
                loadStateByFriend[uid] = LiveState(error: error)
            }
        }
    }
}

// One friend's shared notes from today, for FriendTodayView. Owned per
// screen rather than as a singleton, so nothing is shared between friends:
// start() resets every property, and the listener lives only between the
// screen's onAppear and onDisappear. refreshDayIfNeeded() restarts it when
// the calendar day has moved on, so the screen rolls over at midnight.
@MainActor
final class FriendTodayListener: ObservableObject {
    @Published private(set) var notes: [FriendNote] = []
    @Published private(set) var state: LiveState = .loading
    @Published private(set) var day = FriendDay()

    private var listener: ListenerRegistration?
    private let timeout = LiveTimeout()
    private var friendUID: String?

    func start(friendUID: String) {
        stop()
        self.friendUID = friendUID
        notes = []
        state = .loading
        day = FriendDay()
        attach(friendUID: friendUID, day: day)
    }

    func stop() {
        listener?.remove()
        listener = nil
        timeout.cancel()
    }

    // The Retry button, and the day change.
    func restart() {
        guard let friendUID else { return }
        start(friendUID: friendUID)
    }

    func refreshDayIfNeeded() {
        guard friendUID != nil, FriendDay() != day else { return }
        restart()
    }

    private func attach(friendUID: String, day: FriendDay) {
        timeout.start { [weak self] in
            guard let self, self.friendUID == friendUID, self.state == .loading else { return }
            self.stop()
            self.state = .failed
        }

        listener = day.sharedNotesQuery(friendUID: friendUID)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self, self.friendUID == friendUID, self.day == day, self.listener != nil else { return }

                if let error {
                    self.stop()
                    self.state = LiveState(error: error)
                    return
                }
                guard let snapshot else { return }

                // An empty cache answer only means nothing is cached yet.
                if snapshot.documents.isEmpty, snapshot.metadata.isFromCache, self.state != .loaded {
                    return
                }

                self.timeout.cancel()
                // The query is newest first, the chain reads oldest first.
                self.notes = snapshot.decoded(as: FriendNote.self)
                    .filter { day.contains($0.createdAt) }
                    .sorted { $0.createdAt < $1.createdAt }
                self.state = .loaded
            }
    }
}
