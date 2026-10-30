import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

// A note shared with a friend, as stored in Firestore's `sharedNotes`
// collection. This is a copy, not a live reference to the sender's
// SwiftData Note, sharing copies content rather than syncing the whole
// local database.
struct SharedNote: Codable, Identifiable {
    @DocumentID var id: String?
    var fromUID: String
    var toUID: String
    var text: String
    var createdAt: Date
    var sharedAt: Date
}

// Shares a note with a friend once a friend request has been accepted.
// This reuses the same Firestore project and friendships data
// FriendService already manages, no separate sync mechanism is needed.
@MainActor
final class SharingService {
    static let shared = SharingService()
    private let db = Firestore.firestore()

    // Copies a note's text into a new document scoped to the recipient.
    // Photo sharing would extend this the same way, uploading the
    // image to Firebase Cloud Storage and storing its path alongside the
    // text, but is left out of this stage since the base sharing flow is
    // the Week 8 target.
    func share(note: Note, with friend: FirestoreUser) async throws {
        guard let myUID = Auth.auth().currentUser?.uid, let friendUID = friend.id else { return }

        let data: [String: Any] = [
            "fromUID": myUID,
            "toUID": friendUID,
            "text": note.text,
            "createdAt": note.createdAt,
            "sharedAt": Date(),
        ]

        try await db.collection("sharedNotes").addDocument(data: data)
    }

    // Listens live for notes shared with the signed-in user by anyone in
    // their friends, newest first. Returns the ListenerRegistration so
    // the caller (SharedNotesStore) can detach it on sign out.
    @discardableResult
    func listenForSharedNotes(onChange: @escaping ([SharedNote], Error?) -> Void) -> ListenerRegistration? {
        guard let myUID = Auth.auth().currentUser?.uid else { return nil }
        return db.collection("sharedNotes")
            .whereField("toUID", isEqualTo: myUID)
            .order(by: "sharedAt", descending: true)
            .addSnapshotListener { snapshot, error in
                onChange(snapshot?.decoded(as: SharedNote.self) ?? [], error)
            }
    }
}

// Wraps SharingService's live listener in an ObservableObject so
// HomeView can show, per friend, the most recent note they've shared
// with me. Started once when the signed-in UI first appears and
// stopped on sign out, the same lifecycle as FriendService and
// GardenService.
@MainActor
final class SharedNotesStore: ObservableObject {
    static let shared = SharedNotesStore()
    private init() {}

    @Published private(set) var recentNotes: [SharedNote] = []
    private var listener: ListenerRegistration?

    // The latest shared note from each sender, keyed by their uid.
    // `recentNotes` is already sorted newest first, so the first match
    // per sender is their latest.
    var latestNoteBySender: [String: SharedNote] {
        var result: [String: SharedNote] = [:]
        for note in recentNotes where result[note.fromUID] == nil {
            result[note.fromUID] = note
        }
        return result
    }

    func startListening() {
        guard listener == nil else { return }
        listener = SharingService.shared.listenForSharedNotes { [weak self] notes, _ in
            self?.recentNotes = notes
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        recentNotes = []
    }
}
