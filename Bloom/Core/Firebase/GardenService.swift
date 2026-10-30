import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// One person's plant in the Shared Garden.
struct GardenPlant: Identifiable, Equatable {
    let id: String // uid
    let username: String
    let currentStreak: Int
    let plantState: PlantState?
    // The friend's display name, nil for "You" and for friends who
    // don't have one yet. The streak rows show it above @username.
    var displayName: String? = nil
    var hasAvatar = false
    var avatarUpdatedAt: Date? = nil
    // My own plant reads its picture from MyAvatar, which updates the
    // moment I change it, rather than from a friends snapshot.
    var isMe = false

    var shownName: String { displayName ?? username }
}

// Builds the Shared Garden from the signed-in user's own `streaks/{uid}`
// document plus one for each person the Greenhouse is showing: all friends
// (the first 10 by name) or the members of the selected circle. Every
// document is its own single-document listener, never a collection query,
// since a person can only read their own streak document and their
// friends', individually.
@MainActor
final class GardenService: ObservableObject {
    static let shared = GardenService()
    private init() {}

    private let db = Firestore.firestore()
    // Me plus up to 10 friends.
    static let maxPlants = 11

    @Published private(set) var plants: [GardenPlant] = []

    private var orderedUIDs: [String] = []
    private var usernames: [String: String] = [:]
    private var displayNames: [String: String] = [:]
    private var avatars: [String: (hasAvatar: Bool, updatedAt: Date?)] = [:]
    private var streakSnapshots: [String: (currentStreak: Int, lastPostDate: Date?)] = [:]
    private var listeners: [String: ListenerRegistration] = [:]

    // Called by the Greenhouse whenever the selection or the friends change.
    // Listeners are kept for people who stay, removed for people who left and
    // added for new people, nothing is rebuilt from scratch.
    func setPeople(friends: [FirestoreUser]) {
        guard let myUID = Auth.auth().currentUser?.uid else { return }
        updatePeople(myUID: myUID, friends: friends)
    }

    // Detaches every per-person listener and clears what they'd
    // loaded, so a newly signed-in user doesn't see the previous
    // account's garden.
    func stopListening() {
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
        orderedUIDs = []
        usernames = [:]
        displayNames = [:]
        avatars = [:]
        streakSnapshots = [:]
        plants = []
    }

    private func updatePeople(myUID: String, friends: [FirestoreUser]) {
        var people: [(uid: String, username: String)] = [(myUID, "You")]
        people.append(contentsOf: friends.compactMap { friend in
            friend.id.map { (uid: $0, username: friend.username) }
        })
        people = Array(people.prefix(Self.maxPlants))

        orderedUIDs = people.map(\.uid)
        usernames = Dictionary(people.map { ($0.uid, $0.username) }, uniquingKeysWith: { first, _ in first })
        displayNames = [:]
        avatars = [:]
        for friend in friends {
            guard let id = friend.id else { continue }
            displayNames[id] = friend.shownName
            avatars[id] = (friend.hasAvatar ?? false, friend.avatarUpdatedAt)
        }

        let currentUIDs = Set(orderedUIDs)
        for uid in listeners.keys where !currentUIDs.contains(uid) {
            listeners[uid]?.remove()
            listeners.removeValue(forKey: uid)
            streakSnapshots.removeValue(forKey: uid)
        }

        for person in people where listeners[person.uid] == nil {
            listeners[person.uid] = db.collection("streaks").document(person.uid)
                .addSnapshotListener { [weak self] snapshot, error in
                    self?.handleSnapshot(uid: person.uid, snapshot: snapshot, error: error)
                }
        }

        rebuildPlants()
    }

    private func handleSnapshot(uid: String, snapshot: DocumentSnapshot?, error: Error?) {
        #if DEBUG
        if let error {
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain, nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                print("GardenService: permission denied reading streaks/\(uid). " +
                    "The streaks Firestore security rules probably haven't been published yet.")
            } else {
                print("GardenService: error reading streaks/\(uid): \(error)")
            }
        }
        #endif

        if let data = snapshot?.data() {
            let currentStreak = data["currentStreak"] as? Int ?? 0
            let lastPostDate = (data["lastPostDate"] as? Timestamp)?.dateValue()
            streakSnapshots[uid] = (currentStreak, lastPostDate)
        } else {
            streakSnapshots.removeValue(forKey: uid)
        }
        rebuildPlants()
    }

    private func rebuildPlants() {
        let today = Date()
        plants = orderedUIDs.map { uid in
            let snapshot = streakSnapshots[uid]
            return GardenPlant(
                id: uid,
                username: usernames[uid] ?? "Someone",
                currentStreak: snapshot?.currentStreak ?? 0,
                plantState: GrowthState.plantState(lastPostDate: snapshot?.lastPostDate, today: today),
                displayName: displayNames[uid],
                hasAvatar: avatars[uid]?.hasAvatar ?? false,
                avatarUpdatedAt: avatars[uid]?.updatedAt,
                isMe: uid == Auth.auth().currentUser?.uid
            )
        }
    }
}
