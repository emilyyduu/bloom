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
    private let audioStore: AudioStore = AudioStores.current

    private var isRestoring = false
    private var isSyncingPending = false
    // Bumped on sign out. A run still in flight for the previous account
    // only clears its own in progress flag, never the next account's.
    private var generation = 0

    // Called on sign out, so the next account's restore and sync are
    // never skipped because the previous account's run was still going.
    func reset() {
        generation += 1
        isRestoring = false
        isSyncingPending = false
    }

    // A context is only used if it is the signed-in account's own store,
    // so a context from a previous account (say, in a Task that outlived
    // its view) can never be backed up under the new account's uid.
    private func ownsContext(_ context: ModelContext, uid: String?) -> Bool {
        StoreManager.shared.owns(context, uid: uid)
    }

    // MARK: - Upload

    // Fire-and-forget upload for a single just-saved note. Never
    // blocks the caller; failures are silent. A failed note keeps
    // syncedAt == nil, so syncPending retries it later.
    func upload(_ note: Note) {
        Task { try? await uploadNote(note) }
    }

    // The same upload, awaited, for a notification action that must
    // finish its work before the app can be suspended again.
    func uploadAndWait(_ note: Note) async throws {
        try await uploadNote(note)
    }

    // The photo goes first so a note is never written with hasPhoto
    // true before its photo exists. If the photo step throws, the note
    // is not written and syncedAt stays nil, so it retries.
    private func uploadNote(_ note: Note) async throws {
        guard let uid = note.ownerUID else { return }

        try await syncPhoto(for: note, ownerUID: uid)
        // The memo goes before the note too, so a note is never written
        // with hasAudio true before its audio exists. If this throws the
        // note isn't written and syncedAt stays nil, so it retries.
        try await syncAudio(for: note, ownerUID: uid)

        let data = noteData(for: note)

        try await db.collection("users").document(uid)
            .collection("notes").document(note.id.uuidString)
            .setData(data)


        note.syncedAt = Date()
        try? note.modelContext?.save()

        tellFriendsIfJustShared(note, ownerUID: uid)
    }

    // Writes "shared a note" into each accepted friend's activity, once
    // per note, and only for a note posted or shared within an hour of
    // creating it. Bulk sharing of old notes never comes through here.
    private func tellFriendsIfJustShared(_ note: Note, ownerUID: String) {
        guard !note.isDraft, note.sharedWithFriends,
              Date().timeIntervalSince(note.createdAt) < 3600 else { return }
        let noteID = note.id.uuidString
        guard !AccountDefaults.hasNotifiedFriends(aboutNote: noteID) else { return }

        let friendUIDs = FriendService.shared.friends.compactMap(\.id)
        let text = note.text
        Task { await ActivityWriter.noteShared(noteID: noteID, ownerUID: ownerUID, text: text, friendUIDs: friendUIDs) }
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
            } else if note.photoSyncedAt != nil {
                try await photoStore.delete(ownerUID: ownerUID, noteID: noteID)
                note.photoSyncedAt = nil
            }
        } catch {
            throw error
        }
    }

    private enum PhotoSyncError: Error {
        case couldNotCompress
    }

    // Brings the backed-up voice memo in line with the local one, same
    // pattern as syncPhoto: a new or replaced memo is uploaded over any
    // old one, a removed one has its backup deleted. A memo over the
    // size limit is never uploaded.
    private func syncAudio(for note: Note, ownerUID: String) async throws {
        let noteID = note.id.uuidString

        do {
            if let url = note.audioURL {
                guard note.audioSyncedAt == nil else { return }
                let data = try Data(contentsOf: url)
                guard data.count <= AudioLimits.maxBytes else { throw AudioStoreError.tooLarge }
                try await audioStore.upload(data, ownerUID: ownerUID, noteID: noteID)
                note.audioSyncedAt = Date()
            } else if note.audioSyncedAt != nil {
                try await audioStore.delete(ownerUID: ownerUID, noteID: noteID)
                note.audioSyncedAt = nil
            }
        } catch {
            throw error
        }
    }

    // The document carries these seven fields, plus pinnedAt while the
    // note is pinned. A draft is never written as shared or pinned
    // regardless of what is held locally, since the security rules
    // reject a shared draft and only posted notes can be pinned.
    // hasPhoto is only true once the photo document really exists.
    // setData replaces the whole document, so an unpinned note simply
    // has no pinnedAt.
    private func noteData(for note: Note) -> [String: Any] {
        let isPinned = !note.isDraft && note.isPinned
        // Like hasPhoto, only true once the memo document really exists.
        let hasAudio = note.hasAudio && note.audioSyncedAt != nil
        var data: [String: Any] = [
            "text": note.text,
            "createdAt": Timestamp(date: note.createdAt),
            "isDraft": note.isDraft,
            "updatedAt": Timestamp(date: Date()),
            "sharedWithFriends": note.isDraft ? false : note.sharedWithFriends,
            "hasPhoto": note.hasPhoto && note.photoSyncedAt != nil,
            "isPinned": isPinned,
            "hasAudio": hasAudio,
        ]
        if hasAudio, let audioSeconds = note.audioSeconds {
            data["audioSeconds"] = audioSeconds
        }
        if isPinned {
            data["pinnedAt"] = Timestamp(date: note.pinnedAt ?? Date())
        }
        return data
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
        let mayHaveAudioBackup = note.audioFileName != nil || note.audioSyncedAt != nil
        Task {
            do {
                try await db.collection("users").document(uid).collection("notes").document(noteID).delete()
            } catch {
            }

            if mayHaveAudioBackup {
                do {
                    try await audioStore.delete(ownerUID: uid, noteID: noteID)
                } catch {
                }
            }

            guard mayHavePhotoBackup else { return }
            do {
                try await photoStore.delete(ownerUID: uid, noteID: noteID)
            } catch {
            }
        }
    }

    // MARK: - Deleting a note completely

    // Step 1 and 2 of a delete, all local and instant: the id goes on
    // this account's pending deletions list first, so a failed or
    // interrupted cloud delete can never bring the note back. Then the
    // note and its photo and audio files go. An attached Library entry
    // is detached, not deleted. Returns the id for finishDeletion.
    func beginDeletion(of note: Note, context: ModelContext) -> String? {
        guard let uid = Auth.auth().currentUser?.uid, ownsContext(context, uid: uid) else { return nil }
        let noteID = note.id.uuidString

        AccountDefaults.addPendingDeletion(noteID, uid: uid)

        if let fileName = note.photoFileName {
            try? FileManager.default.removeItem(at: FileManager.documentsDirectory.appendingPathComponent(fileName))
        }
        note.deleteAudioFile()
        note.mediaLogEntry?.note = nil
        context.delete(note)
        try? context.save()
        return noteID
    }

    // Steps 3 and 4: the streak and reminders are recomputed without
    // the note, then the cloud copies are removed.
    func finishDeletion(noteID: String, context: ModelContext) async {
        await StreakSyncService.shared.sync(context: context)
        await NotificationScheduler.shared.refreshReminders(context: context)
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await deleteRemote(noteID: noteID, uid: uid)
    }

    // Removes users/{uid}/notes/{id}, photos/{id}, audio/{id} (a
    // document that doesn't exist is fine) and every comment, then
    // takes the id off the pending list. Any failure leaves the id on
    // the list, and syncPending tries again.
    private func deleteRemote(noteID: String, uid: String) async {
        do {
            let noteRef = db.collection("users").document(uid).collection("notes").document(noteID)
            try await noteRef.delete()
            try await photoStore.delete(ownerUID: uid, noteID: noteID)
            try await audioStore.delete(ownerUID: uid, noteID: noteID)
            try await deleteComments(of: noteRef)
            AccountDefaults.removePendingDeletion(noteID, uid: uid)
        } catch {
        }
    }

    // Firestore doesn't cascade, so comments go in batches of 20.
    private func deleteComments(of noteRef: DocumentReference) async throws {
        while true {
            let snapshot = try await noteRef.collection("comments").limit(to: 20).getDocuments()
            guard !snapshot.documents.isEmpty else { return }
            let batch = db.batch()
            for document in snapshot.documents { batch.deleteDocument(document.reference) }
            try await batch.commit()
        }
    }

    private func retryPendingDeletions(uid: String) async {
        for noteID in AccountDefaults.pendingDeletions(uid: uid) {
            await deleteRemote(noteID: noteID, uid: uid)
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

    // MARK: - Pinning

    // Pins or unpins a posted note. Local first, like the rest of the
    // app: the change is saved straight away and syncedAt is cleared so
    // the note shows as pending, then the upload (which stamps
    // updatedAt) runs in the background. A failed upload leaves
    // syncedAt nil, so syncPending retries it. The limit is checked by
    // the caller, see Note.pinLimit. A draft is never pinned.
    func setPinned(_ isPinned: Bool, for note: Note) {
        guard !note.isDraft || !isPinned else { return }
        note.isPinned = isPinned
        note.pinnedAt = isPinned ? Date() : nil
        note.syncedAt = nil
        try? note.modelContext?.save()
        upload(note)
    }

    // Sets sharedWithFriends on every non-draft note at once, for the
    // Settings "Share all my past notes" / "Stop sharing all notes"
    // buttons. Every note's full document is rewritten, which also
    // fixes old backups that never had the sharedWithFriends field.
    // Photos are synced first, a note whose photo fails is left
    // pending instead of being written. Firestore batches cap at 500
    // writes, so notes are uploaded in chunks.
    func setSharedWithFriendsForAllNotes(_ isShared: Bool, context: ModelContext) async {
        guard let uid = Auth.auth().currentUser?.uid, ownsContext(context, uid: uid) else { return }

        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { !$0.isDraft })
        guard let notes = try? context.fetch(descriptor), !notes.isEmpty else {
            return
        }

        for note in notes {
            note.sharedWithFriends = isShared
            note.syncedAt = nil
            if note.ownerUID == nil { note.ownerUID = uid }
        }
        try? context.save()

        var ready: [Note] = []
        for note in notes {
            guard let noteUID = note.ownerUID else { continue }
            do {
                try await syncPhoto(for: note, ownerUID: noteUID)
                try await syncAudio(for: note, ownerUID: noteUID)
                ready.append(note)
            } catch {}
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
                for note in chunk {
                    note.syncedAt = Date()
                }
            } catch {}
        }

        try? context.save()
    }

    // MARK: - Photo backfill

    // For notes that were backed up before photo sync existed: clears
    // syncedAt on every note that has a local photo but no photo
    // backup, so syncPending uploads the photo and rewrites the note
    // with hasPhoto. The caller guards this to run only once.
    func queuePhotosForBackfill(context: ModelContext) {
        guard ownsContext(context, uid: Auth.auth().currentUser?.uid) else { return }
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate {
            $0.photoFileName != nil && $0.syncedAt != nil && $0.photoSyncedAt == nil
        })
        guard let notes = try? context.fetch(descriptor) else { return }

        for note in notes { note.syncedAt = nil }
        try? context.save()

    }

    // MARK: - Sync pending

    // Uploads every local note that hasn't made it to Firestore yet.
    // Notes created before this feature existed have ownerUID == nil
    // and get stamped with the current uid first. A note already
    // owned by a different account (e.g. a previous sign-in's unsynced
    // draft still sitting in the local store) is never uploaded.
    func syncPending(context: ModelContext) async {
        guard !isSyncingPending, let uid = Auth.auth().currentUser?.uid,
              ownsContext(context, uid: uid) else { return }
        isSyncingPending = true
        let startedGeneration = generation
        defer { if startedGeneration == generation { isSyncingPending = false } }

        await retryPendingDeletions(uid: uid)

        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.syncedAt == nil })
        guard let candidates = try? context.fetch(descriptor) else { return }

        for note in candidates {
            if note.ownerUID == nil {
                note.ownerUID = uid
            } else if note.ownerUID != uid {
                continue
            }

            try? await uploadNote(note)
        }

        try? context.save()
    }

    // MARK: - Restore

    // Fetches users/{uid}/notes once (no listener) and inserts any
    // document that isn't already a local note. Run after sign-in so a
    // reinstall gets every previously backed-up note back. A note with
    // hasPhoto also gets its photo document downloaded into Documents.
    // If that download fails the note is skipped, not inserted, so the
    // next restore retries it instead of losing the photo for good.
    func restore(context: ModelContext) async {
        guard !isRestoring, let uid = Auth.auth().currentUser?.uid,
              ownsContext(context, uid: uid) else { return }
        isRestoring = true
        let startedGeneration = generation
        defer { if startedGeneration == generation { isRestoring = false } }

        let existingIDs: Set<String>
        if let existingNotes = try? context.fetch(FetchDescriptor<Note>()) {
            existingIDs = Set(existingNotes.map { $0.id.uuidString })
        } else {
            existingIDs = []
        }

        // A note deleted here whose cloud delete hasn't finished must
        // not come back.
        let pendingDeletions = Set(AccountDefaults.pendingDeletions(uid: uid))

        let snapshot: QuerySnapshot
        do {
            snapshot = try await db.collection("users").document(uid).collection("notes").getDocuments()
        } catch {
            return
        }

        var restored = 0

        for document in snapshot.documents {
            guard !existingIDs.contains(document.documentID),
                  !pendingDeletions.contains(document.documentID) else { continue }

            guard let uuid = UUID(uuidString: document.documentID) else { continue }

            let data = document.data()
            guard let text = data["text"] as? String,
                  let createdAtTimestamp = data["createdAt"] as? Timestamp,
                  let isDraft = data["isDraft"] as? Bool else { continue }

            var restoredPhotoFileName: String?
            if data["hasPhoto"] as? Bool == true {
                do {
                    if let photoData = try await photoStore.download(ownerUID: uid, noteID: document.documentID) {
                        restoredPhotoFileName = try FileManager.writePhotoData(photoData)
                    }
                } catch {
                    continue
                }
            }

            // Same for a voice memo: a failed download skips the note so
            // the next restore retries it.
            var restoredAudioFileName: String?
            if data["hasAudio"] as? Bool == true {
                do {
                    if let audioData = try await audioStore.download(ownerUID: uid, noteID: document.documentID) {
                        restoredAudioFileName = try FileManager.writeAudioData(audioData)
                    }
                } catch {
                    if let restoredPhotoFileName {
                        try? FileManager.default.removeItem(at: FileManager.documentsDirectory.appendingPathComponent(restoredPhotoFileName))
                    }
                    continue
                }
            }

            let note = Note(text: text, photoFileName: restoredPhotoFileName)
            note.audioFileName = restoredAudioFileName
            note.audioSeconds = restoredAudioFileName == nil ? nil : data["audioSeconds"] as? Int
            note.audioSyncedAt = restoredAudioFileName == nil ? nil : Date()
            note.id = uuid
            note.createdAt = createdAtTimestamp.dateValue()
            note.isDraft = isDraft
            note.ownerUID = uid
            note.syncedAt = Date()
            note.photoSyncedAt = restoredPhotoFileName == nil ? nil : Date()
            note.sharedWithFriends = isDraft ? false : (data["sharedWithFriends"] as? Bool ?? false)
            note.isPinned = isDraft ? false : (data["isPinned"] as? Bool ?? false)
            note.pinnedAt = note.isPinned
                ? ((data["pinnedAt"] as? Timestamp)?.dateValue() ?? note.createdAt)
                : nil
            context.insert(note)

            if !isDraft {
                note.journal = Journal.journal(for: note.createdAt, in: context)
            }

            restored += 1
        }

        try? context.save()


        guard restored > 0 else { return }
        await StreakSyncService.shared.sync(context: context)
        await NotificationScheduler.shared.refreshReminders(context: context)
    }
}
