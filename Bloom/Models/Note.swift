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

    // Whether accepted friends can read this note's backup copy.
    // Always false for drafts, the security rules reject a shared
    // draft outright.
    var sharedWithFriends: Bool

    var journal: Journal?
    var mediaLogEntry: MediaLogEntry?

    init(text: String, photoFileName: String? = nil) {
        self.id = UUID()
        self.text = text
        self.photoFileName = photoFileName
        self.createdAt = Date()
        self.isDraft = true
        self.syncedAt = nil
        self.ownerUID = nil
        self.sharedWithFriends = false
    }
}
