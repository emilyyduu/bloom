import Foundation
import FirebaseAuth

// UserDefaults keys for settings that are about an account's content,
// namespaced with the uid so one account's choice never applies to
// another on the same device. Pure device settings (appearance, the
// daily reminder switch) keep their plain shared keys.
enum AccountDefaults {
    static let shareNewNotesBase = "shareNewNotesWithFriends"
    static let shareNewNotesConfirmationBase = "hasShownShareNewNotesConfirmation"
    static let photoBackfillBase = "hasBackfilledPhotoSync"

    static func key(_ base: String, uid: String? = Auth.auth().currentUser?.uid) -> String {
        "\(base).\(uid ?? "signedOut")"
    }

    // Whether new notes start out shared, for the signed-in account.
    static var shareNewNotes: Bool {
        UserDefaults.standard.bool(forKey: key(shareNewNotesBase))
    }
}
