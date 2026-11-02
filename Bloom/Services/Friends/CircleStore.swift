import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// What can go wrong when changing a circle. Shown to the person as is.
enum CircleError: LocalizedError {
    case limitOfCircles
    case limitOfMembers
    case notAFriend
    case name(CircleNameError)
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .limitOfCircles: return "You can have up to \(CircleLimits.maxCircles) circles."
        case .limitOfMembers: return "A circle can have up to \(CircleLimits.maxMembers) people."
        case .notAFriend: return "Only friends can be added to a circle."
        case .name(let error): return error.message
        case .notSignedIn: return "Sign in to use circles."
        }
    }
}

// My circles, live from users/{myUID}/circles, one listener ordered by
// createdAt. Started once (a listener == nil guard), removed in the account
// reset, and holds the saved Greenhouse and Home selections for the signed
// in account. Circles are never stored in SwiftData.
@MainActor
final class CircleStore: ObservableObject {
    static let shared = CircleStore()

    @Published private(set) var circles: [FriendCircle] = []
    @Published private(set) var state: LiveState = .loading
    @Published private(set) var errorMessage: String?
    // Which circle the Greenhouse shows and which one filters Home's
    // tiles, nil is All friends. Saved per account.
    @Published private(set) var gardenCircleID: String?
    @Published private(set) var homeFilterCircleID: String?

    private var listener: ListenerRegistration?
    private let timeout = LiveTimeout()
    private var friendsCancellable: AnyCancellable?
    private var pruning: Set<String> = []

    private init() {}

    // The circles are known: the first answer, or an error, has arrived.
    var isReady: Bool { state != .loading }

    func circle(id: String?) -> FriendCircle? {
        guard let id else { return nil }
        return circles.first { $0.id == id }
    }

    // nil when saved circle was deleted, which reads as All friends.
    var gardenCircle: FriendCircle? { circle(id: gardenCircleID) }
    var homeFilterCircle: FriendCircle? { circle(id: homeFilterCircleID) }

    // MARK: Members

    // The people still in a circle. Someone who isn't an accepted friend any
    // more is hidden as soon as the friend list is known (and removed from
    // the document), someone who just isn't loaded yet stays.
    func memberUIDs(of circle: FriendCircle) -> [String] {
        guard let confirmed = FriendService.shared.confirmedFriendUIDs else { return circle.memberUIDs }
        return circle.memberUIDs.filter { confirmed.contains($0) }
    }

    func members(of circle: FriendCircle, among friends: [FirestoreUser]) -> [FirestoreUser] {
        let byID = Dictionary(friends.compactMap { friend in friend.id.map { ($0, friend) } }, uniquingKeysWith: { first, _ in first })
        return memberUIDs(of: circle).compactMap { byID[$0] }
    }

    func circles(containing uid: String) -> [FriendCircle] {
        circles.filter { memberUIDs(of: $0).contains(uid) }
    }

    // MARK: Listening

    func startListening() {
        guard listener == nil, let uid = Auth.auth().currentUser?.uid else { return }
        gardenCircleID = AccountDefaults.gardenCircleID
        homeFilterCircleID = AccountDefaults.homeCircleFilterID
        state = .loading
        errorMessage = nil

        timeout.start { [weak self] in
            guard let self, self.state == .loading else { return }
            self.listener?.remove()
            self.listener = nil
            self.state = .failed
            self.errorMessage = "Couldn\u{2019}t load your circles"
        }

        listener = Firestore.firestore().collection("users").document(uid).collection("circles")
            .order(by: "createdAt")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                self.timeout.cancel()

                if let error {
                    self.listener?.remove()
                    self.listener = nil
                    let failure = LiveState(error: error)
                    self.state = failure
                    self.errorMessage = failure == .permissionDenied
                        ? "You can\u{2019}t see your circles"
                        : "Couldn\u{2019}t load your circles"
                    return
                }
                guard let snapshot else { return }

                // A circle that doesn't decode is skipped, not fatal.
                self.circles = snapshot.documents.compactMap { FriendCircle(document: $0) }
                self.state = .loaded
                self.errorMessage = nil
                self.reconcileSelections()
                self.prune(confirmed: FriendService.shared.confirmedFriendUIDs)
            }

        friendsCancellable = FriendService.shared.$confirmedFriendUIDs.sink { [weak self] confirmed in
            self?.prune(confirmed: confirmed)
        }
    }

    // The Retry button.
    func retry() {
        stopListening()
        startListening()
    }

    // The account reset: nothing about this account stays in memory.
    func stopListening() {
        listener?.remove()
        listener = nil
        timeout.cancel()
        friendsCancellable?.cancel()
        friendsCancellable = nil
        pruning = []
        circles = []
        state = .loading
        errorMessage = nil
        gardenCircleID = nil
        homeFilterCircleID = nil
    }

    // A saved selection whose circle is gone falls back to All friends.
    private func reconcileSelections() {
        guard isReady else { return }
        if gardenCircleID != nil, circle(id: gardenCircleID) == nil { selectGardenCircle(nil) }
        if homeFilterCircleID != nil, circle(id: homeFilterCircleID) == nil { selectHomeFilter(nil) }
    }

    func selectGardenCircle(_ id: String?) {
        gardenCircleID = id
        AccountDefaults.gardenCircleID = id
    }

    func selectHomeFilter(_ id: String?) {
        homeFilterCircleID = id
        AccountDefaults.homeCircleFilterID = id
    }

    // Removes people who are no longer accepted friends from the circle
    // documents. Does nothing until the friend list has come from the server.
    private func prune(confirmed: Set<String>?) {
        guard state == .loaded, let confirmed else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        for circle in circles {
            let stale = circle.memberUIDs.filter { !confirmed.contains($0) }
            guard !stale.isEmpty, !pruning.contains(circle.id) else { continue }
            pruning.insert(circle.id)
            let reference = Firestore.firestore().collection("users").document(uid).collection("circles").document(circle.id)
            Task {
                defer { pruning.remove(circle.id) }
                do {
                    try await reference.updateData([
                        "memberUIDs": FieldValue.arrayRemove(stale),
                        "updatedAt": Timestamp(date: Date()),
                    ])
                } catch {
                    errorMessage = "Couldn\u{2019}t update a circle"
                }
            }
        }
    }

    // MARK: Changes

    private var collection: CollectionReference? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return Firestore.firestore().collection("users").document(uid).collection("circles")
    }

    private func isFriend(_ uid: String) -> Bool {
        if let confirmed = FriendService.shared.confirmedFriendUIDs { return confirmed.contains(uid) }
        return FriendService.shared.friends.contains { $0.id == uid }
    }

    @discardableResult
    func create(name: String, memberUIDs: [String]) async throws -> FriendCircle {
        guard CircleLimits.canAdd(current: circles.count, limit: CircleLimits.maxCircles) else { throw CircleError.limitOfCircles }
        if let problem = CircleLimits.nameError(name, existingNames: circles.map(\.name)) { throw CircleError.name(problem) }

        var seen = Set<String>()
        let members = memberUIDs.filter { seen.insert($0).inserted }
        guard CircleLimits.canAdd(current: 0, adding: members.count) else { throw CircleError.limitOfMembers }
        guard members.allSatisfy(isFriend) else { throw CircleError.notAFriend }

        let now = Date()
        let clean = CircleLimits.trimmed(name)

        guard let collection else { throw CircleError.notSignedIn }
        let reference = collection.document()
        try await reference.setData([
            "name": clean,
            "memberUIDs": members,
            "createdAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now),
        ])
        return FriendCircle(id: reference.documentID, name: clean, memberUIDs: members, createdAt: now, updatedAt: now)
    }

    func rename(_ circle: FriendCircle, to name: String) async throws {
        let others = circles.filter { $0.id != circle.id }.map(\.name)
        if let problem = CircleLimits.nameError(name, existingNames: others) { throw CircleError.name(problem) }
        let clean = CircleLimits.trimmed(name)

        try await change(circle, ["name": clean])
    }

    func delete(_ circle: FriendCircle) async throws {
        guard let collection else { throw CircleError.notSignedIn }
        try await collection.document(circle.id).delete()
        // Don't wait for the listener to fall back to All friends.
        if gardenCircleID == circle.id { selectGardenCircle(nil) }
        if homeFilterCircleID == circle.id { selectHomeFilter(nil) }
    }

    func add(_ uids: [String], to circle: FriendCircle) async throws {
        let current = memberUIDs(of: circle)
        let new = Array(Set(uids).subtracting(current))
        guard !new.isEmpty else { return }
        guard CircleLimits.canAdd(current: current.count, adding: new.count) else { throw CircleError.limitOfMembers }
        guard new.allSatisfy(isFriend) else { throw CircleError.notAFriend }

        try await change(circle, ["memberUIDs": FieldValue.arrayUnion(new)])
    }

    func remove(_ uid: String, from circle: FriendCircle) async throws {
        try await change(circle, ["memberUIDs": FieldValue.arrayRemove([uid])])
    }

    // Tapping a circle in FriendProfileView's menu: in becomes out and back.
    func toggle(_ uid: String, in circle: FriendCircle) async throws {
        if memberUIDs(of: circle).contains(uid) {
            try await remove(uid, from: circle)
        } else {
            try await add([uid], to: circle)
        }
    }

    private func change(_ circle: FriendCircle, _ fields: [String: Any]) async throws {
        guard let collection else { throw CircleError.notSignedIn }
        var data = fields
        data["updatedAt"] = Timestamp(date: Date())
        try await collection.document(circle.id).updateData(data)
    }
}
