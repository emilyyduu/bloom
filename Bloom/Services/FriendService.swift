import Foundation
import FirebaseAuth
import FirebaseFirestore
import Contacts
import Combine

enum FriendRequestStatus: String, Codable {
    case pending
    case accepted
}

struct Friendship: Codable, Identifiable {
    @DocumentID var id: String?
    var fromUID: String
    var toUID: String
    var status: FriendRequestStatus
    var createdAt: Date
}

/// Handles finding a friend, by username or by matching phone contacts,
/// and the request-then-accept flow that follows. Once a request is
/// accepted, SharingService is what actually moves a note between the two
/// accounts; this service only manages who is connected to whom.
@MainActor
final class FriendService: ObservableObject {
    static let shared = FriendService()
    private let db = Firestore.firestore()

    @Published var friends: [FirestoreUser] = []
    @Published var pendingIncoming: [Friendship] = []
    @Published var pendingRequesterNames: [String: String] = [:]

    private var listenersStarted = false

    // MARK: - Search

    /// A direct Firestore query against the `users` collection. This is
    /// an open search by design, a username is something a person
    /// chooses to be findable by.
    func searchByUsername(_ username: String) async throws -> [FirestoreUser] {
        let snapshot = try await db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: username)
            .whereField("username", isLessThanOrEqualTo: username + "\u{f8ff}")
            .limit(to: 20)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FirestoreUser.self) }
    }

    /// Matches phone numbers already saved in the user's contacts against
    /// registered Bloom accounts. Only numbers the device already has
    /// saved are ever checked against `users`, nothing is uploaded in
    /// bulk and an arbitrary number can't be probed this way.
    func searchByContacts() async throws -> [FirestoreUser] {
        let store = CNContactStore()

        let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            store.requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        guard granted else { return [] }

        let keys: [CNKeyDescriptor] = [CNContactPhoneNumbersKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)

        var localNumbers: Set<String> = []
        try store.enumerateContacts(with: request) { contact, _ in
            for number in contact.phoneNumbers {
                localNumbers.insert(Self.normalize(number.value.stringValue))
            }
        }

        guard !localNumbers.isEmpty else { return [] }

        var matches: [FirestoreUser] = []
        // Firestore 'in' queries are capped at 30 values, so numbers are
        // checked in batches rather than one query per contact.
        for chunk in Array(localNumbers).chunked(into: 30) {
            let snapshot = try await db.collection("users")
                .whereField("phoneNumber", in: chunk)
                .getDocuments()
            matches.append(contentsOf: snapshot.documents.compactMap { try? $0.data(as: FirestoreUser.self) })
        }
        return matches
    }

    private static func normalize(_ number: String) -> String {
        number.filter(\.isNumber)
    }

    // MARK: - Requests

    func sendFriendRequest(to user: FirestoreUser) async throws {
        guard let myUID = Auth.auth().currentUser?.uid, let toUID = user.id else { return }
        let data: [String: Any] = [
            "fromUID": myUID,
            "toUID": toUID,
            "status": FriendRequestStatus.pending.rawValue,
            "createdAt": Date(),
        ]
        try await db.collection("friendships").addDocument(data: data)
    }

    func acceptFriendRequest(_ friendship: Friendship) async throws {
        guard let id = friendship.id else { return }
        try await db.collection("friendships").document(id).updateData([
            "status": FriendRequestStatus.accepted.rawValue,
        ])
    }

    // MARK: - Live listeners

    /// Starts two live listeners: one for incoming requests still waiting
    /// on this user, one for already-accepted friendships in either
    /// direction. Safe to call more than once, it only attaches once.
    func startListening() {
        guard !listenersStarted, let myUID = Auth.auth().currentUser?.uid else { return }
        listenersStarted = true

        db.collection("friendships")
            .whereField("toUID", isEqualTo: myUID)
            .whereField("status", isEqualTo: FriendRequestStatus.pending.rawValue)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let requests = snapshot?.documents.compactMap { try? $0.data(as: Friendship.self) } ?? []
                self.pendingIncoming = requests
                Task { await self.loadRequesterNames(for: requests) }
            }

        db.collection("friendships")
            .whereField("status", isEqualTo: FriendRequestStatus.accepted.rawValue)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let friendships = snapshot?.documents.compactMap { try? $0.data(as: Friendship.self) } ?? []
                let friendUIDs = friendships.compactMap { friendship -> String? in
                    if friendship.fromUID == myUID { return friendship.toUID }
                    if friendship.toUID == myUID { return friendship.fromUID }
                    return nil
                }
                Task { await self.loadUsers(uids: friendUIDs, into: \.friends) }
            }
    }

    private func loadRequesterNames(for requests: [Friendship]) async {
        let uids = Array(Set(requests.map(\.fromUID)))
        guard !uids.isEmpty else { return }
        for chunk in uids.chunked(into: 30) {
            if let snapshot = try? await db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments() {
                for doc in snapshot.documents {
                    if let user = try? doc.data(as: FirestoreUser.self), let id = user.id {
                        pendingRequesterNames[id] = user.username
                    }
                }
            }
        }
    }

    private func loadUsers(uids: [String], into keyPath: ReferenceWritableKeyPath<FriendService, [FirestoreUser]>) async {
        guard !uids.isEmpty else { self[keyPath: keyPath] = []; return }
        var loaded: [FirestoreUser] = []
        for chunk in uids.chunked(into: 30) {
            if let snapshot = try? await db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments() {
                loaded.append(contentsOf: snapshot.documents.compactMap { try? $0.data(as: FirestoreUser.self) })
            }
        }
        self[keyPath: keyPath] = loaded
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
