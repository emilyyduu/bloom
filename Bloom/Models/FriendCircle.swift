import Foundation
import FirebaseFirestore

// A named group of up to 10 of my friends, stored only in Firestore at
// users/{myUID}/circles/{circleId} with exactly name, memberUIDs, createdAt
// and updatedAt. Private to me: the people in it aren't told and can't see
// it. A circle never controls who can read a note, sharedWithFriends still
// means every accepted friend.
struct FriendCircle: Identifiable, Hashable {
    let id: String
    var name: String
    var memberUIDs: [String]
    var createdAt: Date
    var updatedAt: Date

    init(id: String, name: String, memberUIDs: [String], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.memberUIDs = memberUIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Fails, so the caller can skip it, when a field is missing or the wrong
    // type. A person listed twice is kept once.
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let name = data["name"] as? String, !name.isEmpty,
              let members = data["memberUIDs"] as? [String],
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() else { return nil }

        var seen = Set<String>()
        self.init(
            id: document.documentID,
            name: name,
            memberUIDs: members.filter { seen.insert($0).inserted },
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

enum CircleNameError: Equatable {
    case empty
    case tooLong
    case duplicate

    var message: String {
        switch self {
        case .empty: return "Give the circle a name."
        case .tooLong: return "Names can be up to \(CircleLimits.maxNameLength) characters."
        case .duplicate: return "You already have a circle with that name."
        }
    }
}

// The limits, as small pure functions so they can be checked on their own.
enum CircleLimits {
    static let maxCircles = 10
    static let maxMembers = 10
    static let maxNameLength = 30

    // How many more fit under `limit` when `current` are already there.
    static func remainingSlots(current: Int, limit: Int = maxMembers) -> Int {
        max(0, limit - max(0, current))
    }

    // Whether `adding` more still fits under `limit`.
    static func canAdd(current: Int, adding: Int = 1, limit: Int = maxMembers) -> Bool {
        adding <= remainingSlots(current: current, limit: limit)
    }

    static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // nil when the name is fine. `existingNames` are the other circles'
    // names (leave out the one being renamed). Case is ignored.
    static func nameError(_ name: String, existingNames: [String]) -> CircleNameError? {
        let clean = trimmed(name)
        if clean.isEmpty { return .empty }
        if clean.count > maxNameLength { return .tooLong }
        if existingNames.contains(where: { trimmed($0).caseInsensitiveCompare(clean) == .orderedSame }) {
            return .duplicate
        }
        return nil
    }
}
