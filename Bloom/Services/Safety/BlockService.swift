import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// The people I have blocked, at users/{me}/blocks/{theirUID} with just a
// createdAt. One live listener, started by ContentView and removed in
// AuthService.resetInMemoryAccountState(). Blocking also deletes any
// friendship or request between us, so they can no longer read my notes, and
// the rules stop them sending me a new request. The app hides what a blocked
// person writes (comments, notifications, search results). They are not told.
@MainActor
final class BlockService: ObservableObject {
    static let shared = BlockService()
    private init() {}

    @Published private(set) var blockedUIDs: Set<String> = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func isBlocked(_ uid: String?) -> Bool {
        guard let uid else { return false }
        return blockedUIDs.contains(uid)
    }

    func startListening() {
        guard listener == nil, let me = Auth.auth().currentUser?.uid else { return }
        listener = db.collection("users").document(me).collection("blocks")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, error == nil, let snapshot else { return }
                self.blockedUIDs = Set(snapshot.documents.map(\.documentID))
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        blockedUIDs = []
    }

    // Blocks someone and ends any friendship or request with them, in one
    // batch, so it either all happens or none of it does.
    func block(uid: String) async throws {
        guard let me = Auth.auth().currentUser?.uid, uid != me else { return }

        var friendships: [DocumentReference] = []
        for (from, to) in [(me, uid), (uid, me)] {
            let snapshot = try await db.collection("friendships")
                .whereField("fromUID", isEqualTo: from)
                .whereField("toUID", isEqualTo: to)
                .getDocuments(source: .server)
            friendships += snapshot.documents.map(\.reference)
        }

        let batch = db.batch()
        batch.setData(
            ["createdAt": Timestamp(date: Date())],
            forDocument: db.collection("users").document(me).collection("blocks").document(uid)
        )
        for reference in friendships { batch.deleteDocument(reference) }
        try await batch.commit()
        blockedUIDs.insert(uid)
    }

    // Unblocking does not bring the friendship back. They would have to
    // send a new request, or I would.
    func unblock(uid: String) async throws {
        guard let me = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(me).collection("blocks").document(uid).delete()
        blockedUIDs.remove(uid)
    }
}
