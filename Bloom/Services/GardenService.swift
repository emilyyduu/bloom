import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// One person's plant in the Shared Circle Garden.
struct GardenPlant: Identifiable, Equatable {
    let id: String // uid
    let username: String
    let currentStreak: Int
    let plantState: PlantState?
}

// Builds the Shared Circle Garden from the signed-in user's own
// `streaks/{uid}` document plus one for each accepted friend, reusing
// FriendService's friends list. Every document is its own
// single-document listener, never a collection query, since a person
// can only read their own streak document and their friends',
// individually.
@MainActor
final class GardenService: ObservableObject {
    static let shared = GardenService()
    private init() {}

    private let db = Firestore.firestore()
    private let maxPlants = 6

    @Published private(set) var plants: [GardenPlant] = []

    private var orderedUIDs: [String] = []
    private var usernames: [String: String] = [:]
    private var streakSnapshots: [String: (currentStreak: Int, lastPostDate: Date?)] = [:]
    private var listeners: [String: ListenerRegistration] = [:]
    private var friendsCancellable: AnyCancellable?

    // Safe to call more than once, it only subscribes once.
    func startListening() {
        guard friendsCancellable == nil, let myUID = Auth.auth().currentUser?.uid else { return }

        friendsCancellable = FriendService.shared.$friends
            .sink { [weak self] friends in
                self?.updatePeople(myUID: myUID, friends: friends)
            }
    }

    // Detaches every per-person listener and clears what they'd
    // loaded, so a newly signed-in user doesn't see the previous
    // account's garden.
    func stopListening() {
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
        friendsCancellable?.cancel()
        friendsCancellable = nil
        orderedUIDs = []
        usernames = [:]
        streakSnapshots = [:]
        plants = []
    }

    private func updatePeople(myUID: String, friends: [FirestoreUser]) {
        var people: [(uid: String, username: String)] = [(myUID, "You")]
        people.append(contentsOf: friends.compactMap { friend in
            friend.id.map { (uid: $0, username: friend.username) }
        })
        people = Array(people.prefix(maxPlants))

        orderedUIDs = people.map(\.uid)
        usernames = Dictionary(uniqueKeysWithValues: people.map { ($0.uid, $0.username) })

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
                plantState: GrowthState.plantState(lastPostDate: snapshot?.lastPostDate, today: today)
            )
        }
    }
}
