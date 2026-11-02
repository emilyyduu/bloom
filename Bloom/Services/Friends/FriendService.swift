import Foundation
import FirebaseAuth
import FirebaseFirestore
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

// Handles finding a friend by username,
// and the request-then-accept flow that follows. This service only
// manages who is connected to whom; notes are shared through
// sharedWithFriends on the note itself.
@MainActor
final class FriendService: ObservableObject {
    static let shared = FriendService()
    private let db = Firestore.firestore()

    @Published var friends: [FirestoreUser] = []
    @Published var pendingIncoming: [Friendship] = []
    @Published var pendingRequesterProfiles: [String: FirestoreUser] = [:]
    @Published var pendingOutgoing: [Friendship] = []
    @Published var pendingRecipientProfiles: [String: FirestoreUser] = [:]
    // The uids of my accepted friends as the friendship documents say, nil
    // until both accepted listeners have heard from the server. Unlike
    // `friends` this doesn't wait for profiles to load and is never a
    // half answer from the cache, so it is safe to remove people from
    // circles against.
    @Published private(set) var confirmedFriendUIDs: Set<String>?
    private var hasServerSentAnswer = false
    private var hasServerReceivedAnswer = false
    // Only ever set from a real snapshot, never from a failed listener.
    private var answeredSentUIDs: Set<String> = []
    private var answeredReceivedUIDs: Set<String> = []

    private var listenersStarted = false
    // Whether the first incoming-requests snapshot has arrived, so only
    // requests that show up after it count as new for the notification.
    private var hasReceivedIncomingSnapshot = false
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

        // Tell the person who asked. Best effort, never fails the accept.
        if let myUID = Auth.auth().currentUser?.uid {
            Task { await ActivityWriter.accepted(myUID: myUID, requesterUID: friendship.fromUID) }
        }
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

    // Ends an accepted friendship without blocking. Deletes the friendship
    // document in whichever direction it was made, in one batch. They can
    // still send a new request later, unlike after a block.
    func removeFriend(uid: String) async throws {
        guard let myUID = Auth.auth().currentUser?.uid, uid != myUID else { return }

        var references: [DocumentReference] = []
        for (from, to) in [(myUID, uid), (uid, myUID)] {
            let snapshot = try await db.collection("friendships")
                .whereField("fromUID", isEqualTo: from)
                .whereField("toUID", isEqualTo: to)
                .getDocuments(source: .server)
            references += snapshot.documents.map(\.reference)
        }

        let batch = db.batch()
        for reference in references { batch.deleteDocument(reference) }
        try await batch.commit()
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
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                let requests = snapshot?.decoded(as: Friendship.self) ?? []
                self.pendingIncoming = requests
                Task { await self.loadRequesterNames(for: requests) }

                if self.hasReceivedIncomingSnapshot, let snapshot {
                    for change in snapshot.documentChanges where change.type == .added {
                        let fromUID = change.document.data()["fromUID"] as? String ?? ""
                        Task { await ActivityNotifier.postRequest(from: fromUID) }
                    }
                }
                if snapshot != nil { self.hasReceivedIncomingSnapshot = true }
            }

        outgoingRequestsListener = db.collection("friendships")
            .whereField("fromUID", isEqualTo: myUID)
            .whereField("status", isEqualTo: FriendRequestStatus.pending.rawValue)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                let requests = snapshot?.decoded(as: Friendship.self) ?? []
                self.pendingOutgoing = requests
                Task { await self.loadRecipientNames(for: requests) }
            }

        sentAcceptedListener = db.collection("friendships")
            .whereField("fromUID", isEqualTo: myUID)
            .whereField("status", isEqualTo: FriendRequestStatus.accepted.rawValue)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                let friendships = snapshot?.decoded(as: Friendship.self) ?? []
                self.sentFriendUIDs = friendships.map(\.toUID)
                // A failed listener leaves the uids empty, which must never
                // look like "no friends" to the circles.
                if let snapshot {
                    if !snapshot.metadata.isFromCache { self.hasServerSentAnswer = true }
                    self.answeredSentUIDs = Set(friendships.map(\.toUID))
                    self.updateConfirmedFriendUIDs()
                }
                Task { await self.reloadFriends() }
            }

        receivedAcceptedListener = db.collection("friendships")
            .whereField("toUID", isEqualTo: myUID)
            .whereField("status", isEqualTo: FriendRequestStatus.accepted.rawValue)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                let friendships = snapshot?.decoded(as: Friendship.self) ?? []
                self.receivedFriendUIDs = friendships.map(\.fromUID)
                if let snapshot {
                    if !snapshot.metadata.isFromCache { self.hasServerReceivedAnswer = true }
                    self.answeredReceivedUIDs = Set(friendships.map(\.fromUID))
                    self.updateConfirmedFriendUIDs()
                }
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
        pendingRequesterProfiles = [:]
        pendingOutgoing = []
        pendingRecipientProfiles = [:]
        listenersStarted = false
        hasReceivedIncomingSnapshot = false
        hasServerSentAnswer = false
        hasServerReceivedAnswer = false
        answeredSentUIDs = []
        answeredReceivedUIDs = []
        confirmedFriendUIDs = nil
    }

    private func updateConfirmedFriendUIDs() {
        guard hasServerSentAnswer, hasServerReceivedAnswer else { return }
        let uids = answeredSentUIDs.union(answeredReceivedUIDs)
        if confirmedFriendUIDs != uids { confirmedFriendUIDs = uids }
    }

    private func reloadFriends() async {
        friends = await fetchUsers(withUIDs: sentFriendUIDs + receivedFriendUIDs)
    }

    private func loadRequesterNames(for requests: [Friendship]) async {
        let uids = Array(Set(requests.map(\.fromUID)))
        for user in await fetchUsers(withUIDs: uids) {
            if let id = user.id { pendingRequesterProfiles[id] = user }
        }
    }

    private func loadRecipientNames(for requests: [Friendship]) async {
        let uids = Array(Set(requests.map(\.toUID)))
        for user in await fetchUsers(withUIDs: uids) {
            if let id = user.id { pendingRecipientProfiles[id] = user }
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
