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

    static let shareToCircleConfirmedBase = "hasConfirmedShareToCircle"
    static let pendingDeletionsBase = "pendingNoteDeletions"

    // Whether this account has already seen the one time "All your
    // friends can read this note and comment on it" confirmation.
    static var hasConfirmedShareToCircle: Bool {
        get { UserDefaults.standard.bool(forKey: key(shareToCircleConfirmedBase)) }
        set { UserDefaults.standard.set(newValue, forKey: key(shareToCircleConfirmedBase)) }
    }

    // Ids (UUID strings) of notes deleted on this device whose cloud
    // copies may not be gone yet. restore() skips them and syncPending
    // keeps retrying until they are removed.
    static func pendingDeletions(uid: String?) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(pendingDeletionsBase, uid: uid)) ?? []
    }

    static func addPendingDeletion(_ noteID: String, uid: String?) {
        var ids = pendingDeletions(uid: uid)
        guard !ids.contains(noteID) else { return }
        ids.append(noteID)
        UserDefaults.standard.set(ids, forKey: key(pendingDeletionsBase, uid: uid))
    }

    static func removePendingDeletion(_ noteID: String, uid: String?) {
        let ids = pendingDeletions(uid: uid).filter { $0 != noteID }
        UserDefaults.standard.set(ids, forKey: key(pendingDeletionsBase, uid: uid))
    }

    // The feed's "unread" cut off. Opening the notifications screen moves
    // it to now. The first time an account is used it starts at now, so
    // nothing older than the install counts as unread.
    static var activityLastSeen: Date {
        get {
            let stored = UserDefaults.standard.double(forKey: key("activityLastSeen"))
            if stored > 0 { return Date(timeIntervalSince1970: stored) }
            let now = Date()
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: key("activityLastSeen"))
            return now
        }
        set { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: key("activityLastSeen")) }
    }

    // How the Journals screens order years, months and days. Per account.
    static var journalSortOrder: JournalSortOrder {
        get {
            JournalSortOrder(rawValue: UserDefaults.standard.string(forKey: key("journalSortOrder")) ?? "") ?? .newestFirst
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key("journalSortOrder")) }
    }

    // The Library's sort and filter choices. Per account.
    static var libraryOptions: LibraryOptions {
        get {
            let defaults = UserDefaults.standard
            func stored(_ name: String) -> String { defaults.string(forKey: key(name)) ?? "" }
            return LibraryOptions(
                sort: LibrarySort(rawValue: stored("librarySort")) ?? .newestAdded,
                type: LibraryTypeFilter(rawValue: stored("libraryTypeFilter")) ?? .all,
                stars: LibraryStarsFilter(rawValue: stored("libraryStarsFilter")) ?? .any,
                review: LibraryReviewFilter(rawValue: stored("libraryReviewFilter")) ?? .any
            )
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.sort.rawValue, forKey: key("librarySort"))
            defaults.set(newValue.type.rawValue, forKey: key("libraryTypeFilter"))
            defaults.set(newValue.stars.rawValue, forKey: key("libraryStarsFilter"))
            defaults.set(newValue.review.rawValue, forKey: key("libraryReviewFilter"))
        }
    }

    // The circle the Greenhouse shows and the circle Home's tiles are
    // filtered to, by circle id. nil means All friends.
    static var gardenCircleID: String? {
        get { UserDefaults.standard.string(forKey: key("gardenCircleID")) }
        set { UserDefaults.standard.set(newValue, forKey: key("gardenCircleID")) }
    }

    static var homeCircleFilterID: String? {
        get { UserDefaults.standard.string(forKey: key("homeCircleFilterID")) }
        set { UserDefaults.standard.set(newValue, forKey: key("homeCircleFilterID")) }
    }

    // Which kinds of activity may show a banner while the app is open.
    // All on by default. The feed always shows everything.
    static let bannerFriendRequestsBase = "bannerFriendRequests"
    static let bannerFriendNotesBase = "bannerFriendNotes"
    static let bannerCommentsBase = "bannerComments"

    static func isBannerEnabled(_ base: String) -> Bool {
        UserDefaults.standard.object(forKey: key(base)) as? Bool ?? true
    }

    // Notes whose "shared a note" activity was already written, so a
    // pin or an edit that uploads the note again never notifies twice.
    static func hasNotifiedFriends(aboutNote noteID: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key("notifiedNoteIDs")) ?? []).contains(noteID)
    }

    static func markNotifiedFriends(aboutNote noteID: String) {
        var ids = UserDefaults.standard.stringArray(forKey: key("notifiedNoteIDs")) ?? []
        guard !ids.contains(noteID) else { return }
        ids.append(noteID)
        UserDefaults.standard.set(Array(ids.suffix(500)), forKey: key("notifiedNoteIDs"))
    }

    static func key(_ base: String, uid: String? = Auth.auth().currentUser?.uid) -> String {
        "\(base).\(uid ?? "signedOut")"
    }

    // Whether new notes start out shared, for the signed-in account.
    static var shareNewNotes: Bool {
        UserDefaults.standard.bool(forKey: key(shareNewNotesBase))
    }
}
