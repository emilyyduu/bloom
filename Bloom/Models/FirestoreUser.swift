import Foundation
import FirebaseFirestore

// The small account record stored in Firestore's `users` collection,
// keyed by Firebase Auth uid. This is what makes an account findable by
// someone else, by username or by a matched phone number, it is not a
// public profile.
struct FirestoreUser: Codable, Identifiable {
    @DocumentID var id: String?
    var username: String
    // Optional so profiles created before display names existed still
    // decode. Use shownName anywhere a person's name is displayed.
    var displayName: String?
    var usernameLower: String?
    var phoneNumber: String?
    var createdAt: Date
    // Set together whenever a profile picture is added. The picture
    // itself lives at users/{uid}/avatar/current, see AvatarStore.
    // avatarUpdatedAt is what AvatarCache keys on, so a changed picture
    // reloads and an unchanged one doesn't.
    var hasAvatar: Bool?
    var avatarUpdatedAt: Date?

    // The name friends see: the display name, or the username for
    // accounts that don't have one yet.
    var shownName: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? username : trimmed
    }
}
