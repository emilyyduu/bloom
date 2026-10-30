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

    private static let journalLines = [
        "Coffee with the team, long overdue catch up.",
        "Long walk by the river after work, needed that.",
        "Finally finished the assignment.",
        "Tried a new ramen place, the broth was unreal.",
        "Slow Sunday. Read, napped, repeated.",
        "Gym in the morning, felt strong.",
        "Rain all day, perfect for a movie.",
        "Called home, it was good to hear everyone.",
    ]

    // A sample journal for one sample friend: about 50 shared notes spread
    // over the last two years, a few days with several notes, newest first,
    // like the real query returns them. The same friend always gets the same
    // notes. Never read from or written to Firestore.
    static func journalNotes(for uid: String) -> [FriendNote] {
        let seed = uid.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let calendar = Calendar.current
        let now = Date()
        var notes: [FriendNote] = []

        for step in 0..<40 {
            let daysBack = step * 18 + seed % 7
            guard let day = calendar.date(byAdding: .day, value: -daysBack, to: now) else { continue }
            // Every tenth day is busy, the rest have one or two notes.
            let count = step % 10 == 3 ? 4 : (step % 4 == 0 ? 2 : 1)
            for position in 0..<count {
                let hour = 8 + (step * 5 + position * 4 + seed) % 13
                let minute = (step * 11 + position * 17) % 60
                guard let when = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), when <= now else { continue }
                notes.append(FriendNote(
                    id: "sample-journal-\(uid)-\(step)-\(position)",
                    text: journalLines[(step + position + seed) % journalLines.count],
                    createdAt: when
                ))
            }
        }
        return notes.sorted { $0.createdAt > $1.createdAt }
    }
}
#endif
