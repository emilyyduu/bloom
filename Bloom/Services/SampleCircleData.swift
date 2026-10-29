#if DEBUG
import Foundation

// DEBUG only. With the sample data switch on (Settings > Debug), the app
// shows these 12 friends and 3 circles instead of reading Firestore, so the
// 10 person limit, Home's chips and the Greenhouse switcher can be seen
// without real accounts. Nothing here is ever read from or written to
// Firestore.
enum SampleCircleData {
    static let isEnabledKey = "gardenSampleDataEnabled"

    private static let people: [(id: String, username: String, name: String)] = [
        ("sample-allison", "allison", "Allison Chen"),
        ("sample-priya", "priya", "Priya Raman"),
        ("sample-tom", "tom", "Tom Nguyen"),
        ("sample-mei", "mei", "Mei Tanaka"),
        ("sample-jordan", "jordan", "Jordan Lee"),
        ("sample-sam", "sam", "Sam Okafor"),
        ("sample-maya", "maya", "Maya Patel"),
        ("sample-theo", "theo", "Theo Marsh"),
        ("sample-lena", "lena", "Lena Fischer"),
        ("sample-kai", "kai", "Kai Brooks"),
        ("sample-noor", "noor", "Noor Haddad"),
        ("sample-ravi", "ravi", "Ravi Menon"),
    ]

    static let friends: [FirestoreUser] = people.map {
        FirestoreUser(id: $0.id, username: $0.username, displayName: $0.name, usernameLower: $0.username, phoneNumber: nil, createdAt: Date())
    }

    static func circles() -> [FriendCircle] {
        let ids = people.map(\.id)
        let now = Date()
        return [
            FriendCircle(id: "sample-circle-close", name: "Close friends", memberUIDs: Array(ids.prefix(2)), createdAt: now.addingTimeInterval(-300), updatedAt: now),
            FriendCircle(id: "sample-circle-uni", name: "Uni", memberUIDs: Array(ids[2..<6]), createdAt: now.addingTimeInterval(-200), updatedAt: now),
            FriendCircle(id: "sample-circle-family", name: "Family", memberUIDs: Array(ids[2..<12]), createdAt: now.addingTimeInterval(-100), updatedAt: now),
        ]
    }
}
#endif
