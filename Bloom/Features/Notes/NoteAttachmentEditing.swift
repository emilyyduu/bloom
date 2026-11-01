import Foundation
import SwiftData

// The one place a note's photo, voice memo and movie or show are changed
// on the note itself. The composer uses it when a note is saved, and a
// Today's Notes card uses it for its icon row, so both do exactly the
// same thing to the files, the fields and the sync flags.
@MainActor
enum NoteAttachmentEditing {
    // Replaces the note's photo with these bytes, or removes it when nil.
    // The old file goes, and photoSyncedAt is cleared so the sync service
    // uploads the new photo over the old backup, or deletes the backup.
    static func setPhoto(_ data: Data?, on note: Note) {
        if let oldFileName = note.photoFileName {
            try? FileManager.default.removeItem(at: FileManager.documentsDirectory.appendingPathComponent(oldFileName))
        }
        note.photoFileName = data.flatMap { try? FileManager.writePhotoData($0) }
        note.photoSyncedAt = nil
    }

    // Makes the note's memo match fileName, or removes it when nil. The
    // old file goes, and audioSyncedAt stays as it was when the memo is
    // removed, so the sync service deletes the old backup too.
    static func setAudio(fileName: String?, seconds: Int?, on note: Note) {
        guard note.audioFileName != fileName else { return }
        note.deleteAudioFile()
        note.audioFileName = fileName
        note.audioSeconds = seconds
        if fileName != nil { note.audioSyncedAt = nil }
    }

    // Creates, updates or removes the note's movie or show to match the
    // draft. A note has at most one entry.
    static func setMedia(_ draft: MediaReviewDraft?, on note: Note, in context: ModelContext) {
        let existing = note.mediaLogEntry
        guard let draft else {
            existing?.deleteCompletely(in: context)
            return
        }
        if let existing, existing.tmdbID == draft.tmdbID {
            existing.apply(draft)
        } else {
            existing?.deleteCompletely(in: context)
            _ = MediaLogEntry.create(from: draft, note: note, in: context)
        }
    }

    // For a change made straight to a posted note: not yet backed up,
    // saved, and uploaded (the upload stamps updatedAt on the document).
    static func commit(_ note: Note, in context: ModelContext) {
        note.syncedAt = nil
        try? context.save()
        NoteSyncService.shared.upload(note)
    }
}
