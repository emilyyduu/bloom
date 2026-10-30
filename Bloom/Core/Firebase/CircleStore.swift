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

    @Published private(set) var realCircles: [FriendCircle] = []
    @Published private(set) var state: LiveState = .loading
    @Published private(set) var errorMessage: String?
    // Which circle the Greenhouse shows and which one filters Home's
    // tiles, nil is All friends. Saved per account.
    @Published private(set) var gardenCircleID: String?
    @Published private(set) var homeFilterCircleID: String?
    // DEBUG sample data, always false in release.
    @Published private(set) var isSampleData = false

    #if DEBUG
    @Published private var sampleCircles: [FriendCircle] = SampleCircleData.circles()
    private var defaultsObserver: NSObjectProtocol?
    #endif

    private var listener: ListenerRegistration?
    private let timeout = LiveTimeout()
    private var friendsCancellable: AnyCancellable?
    private var pruning: Set<String> = []

    private init() {
        #if DEBUG
        isSampleData = UserDefaults.standard.bool(forKey: SampleCircleData.isEnabledKey)
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSampleFlag() }
        }
        #endif
    }

    #if DEBUG
    private func refreshSampleFlag() {
        let enabled = UserDefaults.standard.bool(forKey: SampleCircleData.isEnabledKey)
        guard enabled != isSampleData else { return }
        isSampleData = enabled
        reconcileSelections()
    }
    #endif

    var circles: [FriendCircle] {
        #if DEBUG
        if isSampleData { return sampleCircles }
        #endif
        return realCircles
    }

    // The circles are known: the first answer, or an error, has arrived.
    var isReady: Bool { isSampleData || state != .loading }

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
        #if DEBUG
        if isSampleData { return circle.memberUIDs }
        #endif
        guard let confirmed = FriendService.shared.confirmedFriendUIDs else { return circle.memberUIDs }
        return circle.memberUIDs.filter { confirmed.contains($0) }
    }

    func members(of circle: FriendCircle, among friends: [FirestoreUser]) -> [FirestoreUser] {
        let byID = Dictionary(friends.compactMap { friend in friend.id.map { ($0, friend) } }, uniquingKeysWith: { first, _ in first })
        return memberUIDs(of: circle).compactMap { byID[$0] }
    }

    // My friends, or the 12 sample friends when the DEBUG switch is on.
    func allFriends(real: [FirestoreUser]) -> [FirestoreUser] {
        #if DEBUG
        if isSampleData { return SampleCircleData.friends }
        #endif
        return real
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
        let path = "users/\(uid)/circles"
        LiveLog.event("circles", "start", path: path)

        timeout.start { [weak self] in
            guard let self, self.state == .loading else { return }
            LiveLog.event("circles", "TIMED OUT after \(Int(LiveTimeout.seconds))s", path: path)
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
                    LiveLog.error("circles", path: path, error: error)
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
                LiveLog.snapshot("circles", path: path, count: snapshot.documents.count, fromCache: snapshot.metadata.isFromCache)

                // A circle that doesn't decode is skipped, not fatal.
                let parsed = snapshot.documents.compactMap { FriendCircle(document: $0) }
                #if DEBUG
                if parsed.count != snapshot.documents.count {
                    print("CircleStore: skipped \(snapshot.documents.count - parsed.count) circle document(s) that didn't decode")
                }
                #endif
                self.realCircles = parsed
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
        LiveLog.event("circles", "stop", path: "users/?/circles")
        listener?.remove()
        listener = nil
        timeout.cancel()
        friendsCancellable?.cancel()
        friendsCancellable = nil
        pruning = []
        realCircles = []
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
        guard !isSampleData, state == .loaded, let confirmed else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        for circle in realCircles {
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
                    #if DEBUG
                    logFirestoreError(error, while: "removing former friends from circle \(circle.id)")
                    #endif
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
        #if DEBUG
        if isSampleData { return SampleCircleData.friends.contains { $0.id == uid } }
        #endif
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

        #if DEBUG
        if isSampleData {
            let circle = FriendCircle(id: "sample-circle-\(UUID().uuidString)", name: clean, memberUIDs: members, createdAt: now, updatedAt: now)
            sampleCircles.append(circle)
            return circle
        }
        #endif

        guard let collection else { throw CircleError.notSignedIn }
        let reference = collection.document()
        try await write("creating a circle") {
            try await reference.setData([
                "name": clean,
                "memberUIDs": members,
                "createdAt": Timestamp(date: now),
                "updatedAt": Timestamp(date: now),
            ])
        }
        return FriendCircle(id: reference.documentID, name: clean, memberUIDs: members, createdAt: now, updatedAt: now)
    }

    func rename(_ circle: FriendCircle, to name: String) async throws {
        let others = circles.filter { $0.id != circle.id }.map(\.name)
        if let problem = CircleLimits.nameError(name, existingNames: others) { throw CircleError.name(problem) }
        let clean = CircleLimits.trimmed(name)

        #if DEBUG
        if isSampleData {
            update(&sampleCircles, id: circle.id) { $0.name = clean }
            return
        }
        #endif
        try await change(circle, "renaming a circle", ["name": clean])
    }

    func delete(_ circle: FriendCircle) async throws {
        #if DEBUG
        if isSampleData {
            sampleCircles.removeAll { $0.id == circle.id }
            reconcileSelections()
            return
        }
        #endif
        guard let collection else { throw CircleError.notSignedIn }
        try await write("deleting a circle") { try await collection.document(circle.id).delete() }
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

        #if DEBUG
        if isSampleData {
            update(&sampleCircles, id: circle.id) { $0.memberUIDs += new }
            return
        }
        #endif
        try await change(circle, "adding people to a circle", ["memberUIDs": FieldValue.arrayUnion(new)])
    }

    func remove(_ uid: String, from circle: FriendCircle) async throws {
        #if DEBUG
        if isSampleData {
            update(&sampleCircles, id: circle.id) { $0.memberUIDs.removeAll { $0 == uid } }
            return
        }
        #endif
        try await change(circle, "removing someone from a circle", ["memberUIDs": FieldValue.arrayRemove([uid])])
    }

    // Tapping a circle in FriendProfileView's menu: in becomes out and back.
    func toggle(_ uid: String, in circle: FriendCircle) async throws {
        if memberUIDs(of: circle).contains(uid) {
            try await remove(uid, from: circle)
        } else {
            try await add([uid], to: circle)
        }
    }

    private func change(_ circle: FriendCircle, _ action: String, _ fields: [String: Any]) async throws {
        guard let collection else { throw CircleError.notSignedIn }
        var data = fields
        data["updatedAt"] = Timestamp(date: Date())
        try await write(action) { try await collection.document(circle.id).updateData(data) }
    }

    // Every failed write is printed in DEBUG and then thrown to the screen.
    private func write(_ action: String, _ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch {
            #if DEBUG
            logFirestoreError(error, while: action)
            #endif
            throw error
        }
    }

    #if DEBUG
    private func update(_ list: inout [FriendCircle], id: String, _ edit: (inout FriendCircle) -> Void) {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        edit(&list[index])
        list[index].updatedAt = Date()
    }
    #endif
}
