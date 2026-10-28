import Foundation
import SwiftData

// A single journal entry: text and, optionally, a photo.
@Model
final class Note {
    var id: UUID
    var text: String
    var photoFileName: String?
    var createdAt: Date
    var isDraft: Bool

    // Cloud backup bookkeeping. syncedAt is non-nil once this note has
    // been written to users/{ownerUID}/notes; ownerUID is the uid it
    // was (or will be) backed up under. Both stay nil for notes made
    // before this feature existed, until NoteSyncService.syncPending
    // stamps them.
    var syncedAt: Date?
    var ownerUID: String?

    // Like syncedAt but for the photo backup at users/{ownerUID}/photos.
    // nil means the local photo (if any) still needs uploading, or a
    // removed photo still needs its backup deleted. Cleared whenever
    // the local photo is replaced or removed.
    var photoSyncedAt: Date?

    // Whether accepted friends can read this note's backup copy.
    // Always false for drafts, the security rules reject a shared
    // draft outright. The default must be declared here, not just
    // set in init(), so SwiftData's lightweight migration has a
    // value to backfill onto existing rows for this new attribute.
    var sharedWithFriends: Bool = false

    // Pinned notes show on my profile (and, if shared, on friends'
    // view of it). At most Note.pinLimit at a time, enforced by the
    // pin actions, and only ever on posted notes. Both are additive
    // attributes with declared defaults, so SwiftData's lightweight
    // migration can backfill existing rows.
    var isPinned: Bool = false
    var pinnedAt: Date?

    var journal: Journal?
    var mediaLogEntry: MediaLogEntry?

    init(text: String, photoFileName: String? = nil) {
        self.id = UUID()
        self.text = text
        self.photoFileName = photoFileName
        self.createdAt = Date()
        self.isDraft = true
        self.syncedAt = nil
        self.photoSyncedAt = nil
        self.ownerUID = nil
        self.sharedWithFriends = false
    }
}
