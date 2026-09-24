import Foundation
import FirebaseAuth
import FirebaseFirestore

/// A note shared with a friend, as stored in Firestore's `sharedNotes`
/// collection. This is a copy, not a live reference to the sender's
/// SwiftData Note, sharing copies content rather than syncing the whole
/// local database.
struct SharedNote: Codable, Identifiable {
    @DocumentID var id: String?
    var fromUID: String
    var toUID: String
    var text: String
    var createdAt: Date
    var sharedAt: Date
}

/// Shares a note with a friend once a friend request has been accepted.
/// This reuses the same Firestore project and friendships data
/// FriendService already manages, no separate sync mechanism is needed.
@MainActor
final class SharingService {
    static let shared = SharingService()
    private let db = Firestore.firestore()

    /// Copies a note's text into a new document scoped to the recipient.
    /// Photo sharing would extend this the same way, uploading the
    /// image to Firebase Cloud Storage and storing its path alongside the
    /// text, but is left out of this stage since the base sharing flow is
    /// the Week 8 target.
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

    /// Listens live for notes shared with the signed-in user by anyone in
    /// their circle. Not wired into a screen yet at this build stage, a
    /// "Shared With Me" view is a natural next addition once this is
    /// working.
    func listenForSharedNotes(onChange: @escaping ([SharedNote]) -> Void) {
        guard let myUID = Auth.auth().currentUser?.uid else { return }
        db.collection("sharedNotes")
            .whereField("toUID", isEqualTo: myUID)
            .order(by: "sharedAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                let notes = snapshot?.documents.compactMap { try? $0.data(as: SharedNote.self) } ?? []
                onChange(notes)
            }
    }
}
