import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftData

// Backs up notes to Firestore's users/{uid}/notes/{note.id} and
// restores them on a new install. SwiftData stays the source of
// truth: notes work fully offline, this only mirrors them privately
// to the signed-in account so they survive a reinstall. A note's
// photo is backed up separately through PhotoStore, never inside the
// note document. sharedWithFriends mirrors too, so an accepted friend
// can read a note's backup copy once it's turned on.
@MainActor
final class NoteSyncService {
    static let shared = NoteSyncService()
    private init() {}

    private let db = Firestore.firestore()
    private let photoStore: PhotoStore = PhotoStores.current

    private var isRestoring = false
    private var isSyncingPending = false

    // MARK: - Upload

    // Fire-and-forget upload for a single just-saved note. Never
    // blocks the caller; failures are silent in release and printed
    // in DEBUG. A failed note keeps syncedAt == nil, so syncPending
    // retries it later.
    func upload(_ note: Note) {
        Task {
            do {
                try await uploadNote(note)
                #if DEBUG
                print("NoteSyncService: uploaded note \(note.id.uuidString)")
                #endif
            } catch {
                #if DEBUG
                logFirestoreError(error, while: "uploading note \(note.id.uuidString)")
                #endif
            }
        }
    }

    // The photo goes first so a note is never written with hasPhoto
    // true before its photo exists. If the photo step throws, the note
    // is not written and syncedAt stays nil, so it retries.
    private func uploadNote(_ note: Note) async throws {
        guard let uid = note.ownerUID else { return }

        try await syncPhoto(for: note, ownerUID: uid)

        let data = noteData(for: note)

        try await db.collection("users").document(uid)
            .collection("notes").document(note.id.uuidString)
            .setData(data)

        note.syncedAt = Date()
        try? note.modelContext?.save()
    }

    // Brings the backed-up photo in line with the local one. A new or
    // replaced local photo is compressed and uploaded (overwriting any
    // old one); a removed one has its backup deleted. A photoFileName
    // whose file is gone is treated as no photo.
    private func syncPhoto(for note: Note, ownerUID: String) async throws {
        let noteID = note.id.uuidString

        do {
            if note.hasPhoto, let image = note.photo {
                guard note.photoSyncedAt == nil else { return }
                guard let data = PhotoCompressor.uploadData(from: image) else {
                    throw PhotoSyncError.couldNotCompress
                }
                try await photoStore.upload(data, ownerUID: ownerUID, noteID: noteID)
                note.photoSyncedAt = Date()
                #if DEBUG
                print("NoteSyncService: uploaded photo for \(noteID), \(data.count) bytes")
                #endif
            } else if note.photoSyncedAt != nil {
                try await photoStore.delete(ownerUID: ownerUID, noteID: noteID)
                note.photoSyncedAt = nil
                #if DEBUG
                print("NoteSyncService: deleted photo for \(noteID)")
                #endif
            }
        } catch {
            #if DEBUG
            logFirestoreError(error, while: "syncing photo for note \(noteID). Permission denied here means the photos rules aren't published")
            #endif
            throw error
        }
    }

    private enum PhotoSyncError: Error {
        case couldNotCompress
    }

    // The document always carries exactly these six fields, a draft
    // is never written as shared regardless of what sharedWithFriends
    // holds locally, since the security rules reject a shared draft.
    // hasPhoto is only true once the photo document really exists.
    private func noteData(for note: Note) -> [String: Any] {
        [
            "text": note.text,
            "createdAt": Timestamp(date: note.createdAt),
            "isDraft": note.isDraft,
            "updatedAt": Timestamp(date: Date()),
            "sharedWithFriends": note.isDraft ? false : note.sharedWithFriends,
            "hasPhoto": note.hasPhoto && note.photoSyncedAt != nil,
        ]
    }

    // MARK: - Delete

    // Deletes a note's backup document and its photo document, for
    // when a note that was ever backed up gets deleted locally. A
    // delete on a document that was never actually written is a
    // harmless no-op, so this doesn't need to track "was it really
    // synced" separately.
    func delete(_ note: Note) {
        guard let uid = note.ownerUID else { return }
        let noteID = note.id.uuidString
        let mayHavePhotoBackup = note.hasPhoto || note.photoSyncedAt != nil
        Task {
            do {
                try await db.collection("users").document(uid).collection("notes").document(noteID).delete()
                #if DEBUG
                print("NoteSyncService: deleted note \(noteID)")
                #endif
            } catch {
                #if DEBUG
                logFirestoreError(error, while: "deleting note \(noteID)")
                #endif
            }

            guard mayHavePhotoBackup else { return }
            do {
                try await photoStore.delete(ownerUID: uid, noteID: noteID)
            } catch {
                #if DEBUG
                logFirestoreError(error, while: "deleting photo \(noteID)")
                #endif
            }
        }
    }

    // MARK: - Sharing

    // Toggles sharedWithFriends for an existing note, from the
    // per-note share sheet (the composer just sets the property
    // directly before its first upload). Clears syncedAt first so the
    // note shows as pending until the write confirms, then waits for
    // the upload so the caller can revert its UI on failure. A draft
    // is never set to shared.
    func updateSharedWithFriends(_ isShared: Bool, for note: Note) async throws {
        guard !note.isDraft else { return }
        let previous = note.sharedWithFriends
        note.sharedWithFriends = isShared
        note.syncedAt = nil
        try? note.modelContext?.save()

        do {
            try await uploadNote(note)
        } catch {
            note.sharedWithFriends = previous
            try? note.modelContext?.save()
            throw error
        }
    }

    // Sets sharedWithFriends on every non-draft note at once, for the
    // Settings "Share all my past notes" / "Stop sharing all notes"
    // buttons. Every note's full document is rewritten, which also
    // fixes old backups that never had the sharedWithFriends field.
    // Photos are synced first, a note whose photo fails is left
    // pending instead of being written. Firestore batches cap at 500
    // writes, so notes are uploaded in chunks.
    func setSharedWithFriendsForAllNotes(_ isShared: Bool, context: ModelContext) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { !$0.isDraft })
        guard let notes = try? context.fetch(descriptor), !notes.isEmpty else {
            #if DEBUG
            print("NoteSyncService: setSharedWithFriendsForAllNotes(\(isShared)) - no notes to update")
            #endif
            return
        }

        for note in notes {
            note.sharedWithFriends = isShared
            note.syncedAt = nil
            if note.ownerUID == nil { note.ownerUID = uid }
        }
        try? context.save()

        var updated = 0
        var failed = 0

        var ready: [Note] = []
        for note in notes {
            guard let noteUID = note.ownerUID else { continue }
            do {
                try await syncPhoto(for: note, ownerUID: noteUID)
                ready.append(note)
            } catch {
                failed += 1
            }
        }

        for chunk in ready.chunked(into: 500) {
            let batch = db.batch()
            for note in chunk {
                guard let noteUID = note.ownerUID else { continue }
                let ref = db.collection("users").document(noteUID).collection("notes").document(note.id.uuidString)
                batch.setData(noteData(for: note), forDocument: ref)
            }

            do {
                try await batch.commit()
                for note in chunk { note.syncedAt = Date() }
                updated += chunk.count
            } catch {
                failed += chunk.count
                #if DEBUG
                logFirestoreError(error, while: "bulk-updating sharing for \(chunk.count) notes")
                #endif
            }
        }

        try? context.save()

        #if DEBUG
        print("NoteSyncService: setSharedWithFriendsForAllNotes(\(isShared)) - " +
            "updated \(updated), failed \(failed)")
        #endif
    }

    // MARK: - Photo backfill

    // For notes that were backed up before photo sync existed: clears
    // syncedAt on every note that has a local photo but no photo
    // backup, so syncPending uploads the photo and rewrites the note
    // with hasPhoto. The caller guards this to run only once.
    func queuePhotosForBackfill(context: ModelContext) {
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate {
            $0.photoFileName != nil && $0.syncedAt != nil && $0.photoSyncedAt == nil
        })
        guard let notes = try? context.fetch(descriptor) else { return }

        for note in notes { note.syncedAt = nil }
        try? context.save()

        #if DEBUG
        print("NoteSyncService: photo backfill queued \(notes.count) note(s)")
        #endif
    }

    // MARK: - Sync pending

    // Uploads every local note that hasn't made it to Firestore yet.
    // Notes created before this feature existed have ownerUID == nil
    // and get stamped with the current uid first. A note already
    // owned by a different account (e.g. a previous sign-in's unsynced
    // draft still sitting in the local store) is never uploaded.
    func syncPending(context: ModelContext) async {
        guard !isSyncingPending, let uid = Auth.auth().currentUser?.uid else { return }
        isSyncingPending = true
        defer { isSyncingPending = false }

        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.syncedAt == nil })
        guard let candidates = try? context.fetch(descriptor) else { return }

        var uploaded = 0
        var skippedForAnotherAccount = 0
        var failed = 0

        for note in candidates {
            if note.ownerUID == nil {
                note.ownerUID = uid
            } else if note.ownerUID != uid {
                skippedForAnotherAccount += 1
                continue
            }

            do {
                try await uploadNote(note)
                uploaded += 1
            } catch {
                failed += 1
                #if DEBUG
                logFirestoreError(error, while: "uploading note \(note.id.uuidString)")
                #endif
            }
        }

        try? context.save()

        #if DEBUG
        print("NoteSyncService: syncPending - uploaded \(uploaded), " +
            "skipped \(skippedForAnotherAccount) for another account, failed \(failed)")
        #endif
    }

    // MARK: - Restore

    // Fetches users/{uid}/notes once (no listener) and inserts any
    // document that isn't already a local note. Run after sign-in so a
    // reinstall gets every previously backed-up note back. A note with
    // hasPhoto also gets its photo document downloaded into Documents.
    // If that download fails the note is skipped, not inserted, so the
    // next restore retries it instead of losing the photo for good.
    func restore(context: ModelContext) async {
        guard !isRestoring, let uid = Auth.auth().currentUser?.uid else { return }
        isRestoring = true
        defer { isRestoring = false }

        let existingIDs: Set<String>
        if let existingNotes = try? context.fetch(FetchDescriptor<Note>()) {
            existingIDs = Set(existingNotes.map { $0.id.uuidString })
        } else {
            existingIDs = []
        }

        let snapshot: QuerySnapshot
        do {
            snapshot = try await db.collection("users").document(uid).collection("notes").getDocuments()
        } catch {
            #if DEBUG
            logFirestoreError(error, while: "restoring notes")
            #endif
            return
        }

        var restored = 0
        var failed = 0

        for document in snapshot.documents {
            guard !existingIDs.contains(document.documentID) else { continue }

            guard let uuid = UUID(uuidString: document.documentID) else {
                failed += 1
                continue
            }

            let data = document.data()
            guard let text = data["text"] as? String,
                  let createdAtTimestamp = data["createdAt"] as? Timestamp,
                  let isDraft = data["isDraft"] as? Bool else {
                failed += 1
                continue
            }

            var restoredPhotoFileName: String?
            if data["hasPhoto"] as? Bool == true {
                do {
                    if let photoData = try await photoStore.download(ownerUID: uid, noteID: document.documentID) {
                        restoredPhotoFileName = try FileManager.writePhotoData(photoData)
                    }
                } catch {
                    failed += 1
                    #if DEBUG
                    logFirestoreError(error, while: "restoring photo for note \(document.documentID)")
                    #endif
                    continue
                }
            }

            let note = Note(text: text, photoFileName: restoredPhotoFileName)
            note.id = uuid
            note.createdAt = createdAtTimestamp.dateValue()
            note.isDraft = isDraft
            note.ownerUID = uid
            note.syncedAt = Date()
            note.photoSyncedAt = restoredPhotoFileName == nil ? nil : Date()
            note.sharedWithFriends = isDraft ? false : (data["sharedWithFriends"] as? Bool ?? false)
            context.insert(note)

            if !isDraft {
                note.journal = Journal.journal(for: note.createdAt, in: context)
            }

            restored += 1
        }

        try? context.save()

        #if DEBUG
        print("NoteSyncService: restore - restored \(restored), failed \(failed)")
        #endif

        guard restored > 0 else { return }
        await StreakSyncService.shared.sync(context: context)
        let isReminderEnabled = UserDefaults.standard.bool(forKey: "dailyReminderEnabled")
        await NotificationScheduler.shared.refreshReminders(enabled: isReminderEnabled, context: context)
    }
}
