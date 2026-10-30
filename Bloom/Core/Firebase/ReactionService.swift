import Foundation
import Combine
import FirebaseFirestore

// The six reactions a person can leave on a shared note. Only the raw
// value is ever stored in Firestore, the emoji is the app's own mapping.
enum ReactionKind: String, CaseIterable, Identifiable {
    case love
    case laugh
    case wow
    case sad
    case clap
    case sprout

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .love: return "\u{2764}\u{FE0F}"
        case .laugh: return "\u{1F606}"
        case .wow: return "\u{1F62E}"
        case .sad: return "\u{1F622}"
        case .clap: return "\u{1F44F}"
        case .sprout: return "\u{1F331}"
        }
    }

    var title: String {
        switch self {
        case .love: return "Love"
        case .laugh: return "Laugh"
        case .wow: return "Wow"
        case .sad: return "Sad"
        case .clap: return "Clap"
        case .sprout: return "Sprout"
        }
    }
}

// One person's reaction on a note, stored at
// users/{ownerUID}/notes/{noteId}/reactions/{reactorUID} with exactly
// kind and createdAt. The document id is the reactor's uid, so a person
// has at most one reaction per note. Reactions never touch SwiftData.
struct NoteReaction: Identifiable, Equatable {
    let id: String
    let kind: ReactionKind
    let createdAt: Date
}

// How many reactions a card that isn't showing live data has, loaded
// lazily with a count aggregate and cached for the session, like
// CommentCounts. A failed count is simply absent. The selected card's live
// listener keeps its note's number current.
@MainActor
final class ReactionCounts: ObservableObject {
    static let shared = ReactionCounts()
    private init() {}

    @Published private(set) var counts: [String: Int] = [:]
    private var inFlight: Set<String> = []

    private static func key(ownerUID: String, noteID: String) -> String { "\(ownerUID)/\(noteID)" }

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
            .collection("notes").document(noteID).collection("reactions").count
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

// The live reactions of one note, owned per sheet so nothing is shared
// between notes, like NoteCommentsListener. One listener on the
// reactions subcollection with no filter or orderBy, so no index is
// needed. Attached on appear and removed on disappear.
@MainActor
final class NoteReactionsListener: ObservableObject {
    @Published private(set) var reactions: [NoteReaction] = []
    @Published private(set) var state: LiveState = .loading
    @Published private(set) var errorMessage: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var ownerUID: String?
    private var noteID: String?
    private var errorTask: Task<Void, Never>?
    private let timeout = LiveTimeout()

    private var collection: CollectionReference? {
        guard let ownerUID, let noteID else { return nil }
        return db.collection("users").document(ownerUID).collection("notes").document(noteID).collection("reactions")
    }

    func count(for kind: ReactionKind) -> Int {
        reactions.filter { $0.kind == kind }.count
    }

    func myReaction(uid: String?) -> ReactionKind? {
        guard let uid else { return nil }
        return reactions.first { $0.id == uid }?.kind
    }

    // For one off writes with no listener, such as a notification action:
    // points toggle() at a note without attaching anything. With no
    // reactions loaded, toggle always sets, never removes.
    func prepareForOneOffWrite(ownerUID: String, noteID: String) {
        self.ownerUID = ownerUID
        self.noteID = noteID
    }

    // Starting the note that is already running does nothing, so the
    // sheet can call this from more than one place.
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

        listener = collection?.addSnapshotListener { [weak self] snapshot, error in
            guard let self, self.noteID == noteID, self.ownerUID == ownerUID else { return }
            self.timeout.cancel()

            if let error {
                // Firestore ends a listener that errored.
                self.listener?.remove()
                self.listener = nil
                self.state = LiveState(error: error)
                return
            }
            guard let snapshot else { return }

            self.reactions = snapshot.documents.compactMap(Self.reaction(from:))
            self.state = .loaded
            ReactionCounts.shared.set(self.reactions.count, ownerUID: ownerUID, noteID: noteID)
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
        errorTask?.cancel()
        errorMessage = nil
        reactions = []
        state = .loading
    }

    private static func reaction(from document: QueryDocumentSnapshot) -> NoteReaction? {
        let data = document.data()
        // A kind this version doesn't know is skipped, not a crash.
        guard let kindString = data["kind"] as? String,
              let kind = ReactionKind(rawValue: kindString),
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else { return nil }
        return NoteReaction(id: document.documentID, kind: kind, createdAt: createdAt)
    }

    // Tapping my current reaction removes it, tapping another replaces
    // it. The change shows at once and is put back if the write fails.
    func toggle(_ kind: ReactionKind, myUID: String) async {
        let previous = reactions.first { $0.id == myUID }
        let newKind: ReactionKind? = previous?.kind == kind ? nil : kind
        errorMessage = nil
        apply(newKind, uid: myUID)

        guard let reference = collection?.document(myUID) else { return }

        do {
            if let newKind {
                try await reference.setData([
                    "kind": newKind.rawValue,
                    "createdAt": Timestamp(date: Date()),
                ])
            } else {
                try await reference.delete()
            }
        } catch {
            apply(previous?.kind, uid: myUID, createdAt: previous?.createdAt)
            showError("Couldn\u{2019}t save your reaction. Try again.")
            return
        }

        // Tell the note's owner, unless it's my own note. Best effort.
        if newKind != nil, let ownerUID, let noteID, ownerUID != myUID {
            Task { await ActivityWriter.reacted(noteID: noteID, reactorUID: myUID, noteOwnerUID: ownerUID) }
        }
    }

    // Sets or clears only my own entry, so a failure never disturbs
    // anyone else's reaction that arrived in the meantime.
    private func apply(_ kind: ReactionKind?, uid: String, createdAt: Date? = nil) {
        reactions.removeAll { $0.id == uid }
        if let kind {
            reactions.append(NoteReaction(id: uid, kind: kind, createdAt: createdAt ?? Date()))
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        errorTask?.cancel()
        errorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.errorMessage = nil
        }
    }
}
