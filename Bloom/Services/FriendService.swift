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

// How the signed-in user relates to another account: no connection at
// all, already friends, a request already sent and waiting on them, or
// a request from them already waiting on me.
enum FriendRelationship {
    case none
    case friends
    case outgoingPending
    case incomingPending
}

// Handles finding a friend, by username or by matching phone contacts,
// and the request-then-accept flow that follows. Once a request is
// accepted, SharingService is what actually moves a note between the two
// accounts; this service only manages who is connected to whom.
@MainActor
final class FriendService: ObservableObject {
    static let shared = FriendService()
    private let db = Firestore.firestore()

    @Published var friends: [FirestoreUser] = []
    @Published var pendingIncoming: [Friendship] = []
    @Published var pendingRequesterNames: [String: String] = [:]
    @Published var pendingOutgoing: [Friendship] = []
    @Published var pendingRecipientNames: [String: String] = [:]

    private var listenersStarted = false
    private var incomingRequestsListener: ListenerRegistration?
    private var outgoingRequestsListener: ListenerRegistration?
    private var sentAcceptedListener: ListenerRegistration?
    private var receivedAcceptedListener: ListenerRegistration?

    // The two halves of `friends`, kept separate since they come from
    // two differently-filtered listeners (security rules don't allow a
    // single query across both directions) and are recombined whenever
    // either one updates.
    private var sentFriendUIDs: [String] = []
    private var receivedFriendUIDs: [String] = []

    // Search
    // A direct Firestore query against the `users` collection. This is
    // an open search by design, a username is something a person
    // chooses to be findable by. Firestore queries are case sensitive,
    // so the prefix match runs against the lowercase usernameLower
    // field rather than username itself; results still show the
    // original casing since the whole FirestoreUser is returned.
    func searchByUsername(_ username: String) async throws -> [FirestoreUser] {
        let query = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        let snapshot = try await db.collection("users")
            .whereField("usernameLower", isGreaterThanOrEqualTo: query)
            .whereField("usernameLower", isLessThanOrEqualTo: query + "\u{f8ff}")
            .limit(to: 20)
            .getDocuments()

        let myUID = Auth.auth().currentUser?.uid
        return snapshot.decoded(as: FirestoreUser.self).filter { $0.id != myUID }
    }

    // Matches phone numbers already saved in the user's contacts against
    // registered Bloom accounts. Only numbers the device already has
    // saved are ever checked against `users`, nothing is uploaded in
    // bulk and an arbitrary number can't be probed this way.
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
                localNumbers.insert(PhoneNumber.normalized(number.value.stringValue))
            }
        }

        guard !localNumbers.isEmpty else { return [] }

        // Firestore 'in' queries are capped at 30 values, so numbers are
        // checked in batches rather than one query per contact.
        var matches: [FirestoreUser] = []
        for chunk in Array(localNumbers).chunked(into: 30) {
            let snapshot = try await db.collection("users")
                .whereField("phoneNumber", in: chunk)
                .getDocuments()
            matches.append(contentsOf: snapshot.decoded(as: FirestoreUser.self))
        }
        return matches
    }

    // Requests:
    // Writes the friendship under a fixed `fromUID_toUID` document ID
    // rather than letting Firestore generate one, so the security
    // rules can check who's allowed to create it without a lookup.
    func sendFriendRequest(to user: FirestoreUser) async throws {
        guard let myUID = Auth.auth().currentUser?.uid, let toUID = user.id, myUID != toUID else { return }
        let data: [String: Any] = [
            "fromUID": myUID,
            "toUID": toUID,
            "status": FriendRequestStatus.pending.rawValue,
            "createdAt": Date(),
        ]
        try await db.collection("friendships").document("\(myUID)_\(toUID)").setData(data)
    }

    func acceptFriendRequest(_ friendship: Friendship) async throws {
        guard let id = friendship.id else { return }
        try await db.collection("friendships").document(id).updateData([
            "status": FriendRequestStatus.accepted.rawValue,
        ])
    }

    // Declining someone else's request and cancelling my own both just
    // delete the friendship document, the security rules let either
    // person in it delete it. Kept as two named methods since the two
    // call sites mean different things even though the effect is the
    // same.
    func declineRequest(_ friendship: Friendship) async throws {
        guard let id = friendship.id else { return }
        try await db.collection("friendships").document(id).delete()
    }

    func cancelRequest(_ friendship: Friendship) async throws {
        guard let id = friendship.id else { return }
        try await db.collection("friendships").document(id).delete()
    }

    // How the signed-in user relates to another account, used by
    // AddFriendView so a search result shows the right action (Add,
    // Requested, Accept or Friends) instead of letting a duplicate
    // request go out in either direction.
    func relationship(withUID uid: String) -> FriendRelationship {
        if friends.contains(where: { $0.id == uid }) { return .friends }
        if pendingOutgoing.contains(where: { $0.toUID == uid }) { return .outgoingPending }
        if pendingIncoming.contains(where: { $0.fromUID == uid }) { return .incomingPending }
        return .none
    }

    func incomingRequest(fromUID uid: String) -> Friendship? {
        pendingIncoming.first { $0.fromUID == uid }
    }

    // Live listeners:
    // Starts three live listeners: incoming requests still waiting on
    // this user, accepted friendships this user sent, and accepted
    // friendships this user received. Accepted friendships need two
    // separate listeners rather than one unfiltered-by-user query,
    // since the security rules only allow reading friendships where
    // this user is the sender or the recipient. Safe to call more than
    // once, it only attaches once.
    func startListening() {
        guard !listenersStarted, let myUID = Auth.auth().currentUser?.uid else { return }
        listenersStarted = true

        incomingRequestsListener = db.collection("friendships")
            .whereField("toUID", isEqualTo: myUID)
            .whereField("status", isEqualTo: FriendRequestStatus.pending.rawValue)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let requests = snapshot?.decoded(as: Friendship.self) ?? []
                self.pendingIncoming = requests
                Task { await self.loadRequesterNames(for: requests) }
            }

        outgoingRequestsListener = db.collection("friendships")
            .whereField("fromUID", isEqualTo: myUID)
            .whereField("status", isEqualTo: FriendRequestStatus.pending.rawValue)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let requests = snapshot?.decoded(as: Friendship.self) ?? []
                self.pendingOutgoing = requests
                Task { await self.loadRecipientNames(for: requests) }
            }

        sentAcceptedListener = db.collection("friendships")
            .whereField("fromUID", isEqualTo: myUID)
            .whereField("status", isEqualTo: FriendRequestStatus.accepted.rawValue)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let friendships = snapshot?.decoded(as: Friendship.self) ?? []
                self.sentFriendUIDs = friendships.map(\.toUID)
                Task { await self.reloadFriends() }
            }

        receivedAcceptedListener = db.collection("friendships")
            .whereField("toUID", isEqualTo: myUID)
            .whereField("status", isEqualTo: FriendRequestStatus.accepted.rawValue)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let friendships = snapshot?.decoded(as: Friendship.self) ?? []
                self.receivedFriendUIDs = friendships.map(\.fromUID)
                Task { await self.reloadFriends() }
            }
    }

    // Detaches every listener and clears whatever they'd loaded, so a
    // newly signed-in user doesn't see the previous account's friends
    // and requests. Leaves the service ready for startListening() to be
    // called again.
    func stopListening() {
        incomingRequestsListener?.remove()
        incomingRequestsListener = nil
        outgoingRequestsListener?.remove()
        outgoingRequestsListener = nil
        sentAcceptedListener?.remove()
        sentAcceptedListener = nil
        receivedAcceptedListener?.remove()
        receivedAcceptedListener = nil

        sentFriendUIDs = []
        receivedFriendUIDs = []
        friends = []
        pendingIncoming = []
        pendingRequesterNames = [:]
        pendingOutgoing = []
        pendingRecipientNames = [:]
        listenersStarted = false
    }

    private func reloadFriends() async {
        friends = await fetchUsers(withUIDs: sentFriendUIDs + receivedFriendUIDs)
    }

    private func loadRequesterNames(for requests: [Friendship]) async {
        let uids = Array(Set(requests.map(\.fromUID)))
        for user in await fetchUsers(withUIDs: uids) {
            if let id = user.id { pendingRequesterNames[id] = user.username }
        }
    }

    private func loadRecipientNames(for requests: [Friendship]) async {
        let uids = Array(Set(requests.map(\.toUID)))
        for user in await fetchUsers(withUIDs: uids) {
            if let id = user.id { pendingRecipientNames[id] = user.username }
        }
    }

    // Fetches the user records for a set of UIDs, in batches of 30
    // since that's the limit of a Firestore 'in' query. Shared by the
    // friends and requester-name listeners above, which both start from
    // a list of UIDs and want the matching FirestoreUser records.
    private func fetchUsers(withUIDs uids: [String]) async -> [FirestoreUser] {
        guard !uids.isEmpty else { return [] }
        var users: [FirestoreUser] = []
        for chunk in uids.chunked(into: 30) {
            if let snapshot = try? await db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments() {
                users.append(contentsOf: snapshot.decoded(as: FirestoreUser.self))
            }
        }
        return users
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
