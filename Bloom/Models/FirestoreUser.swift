import Foundation
import FirebaseFirestore

// The small account record stored in Firestore's `users` collection,
// keyed by Firebase Auth uid. This is what makes an account findable by
// someone else, by username or by a matched phone number, it is not a
// public profile.
struct FirestoreUser: Codable, Identifiable {
    @DocumentID var id: String?
    var username: String
    var usernameLower: String?
    var phoneNumber: String?
    var createdAt: Date
}
