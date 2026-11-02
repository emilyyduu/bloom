import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftData

// Backs up the Library (movie and show log entries) privately to
// users/{uid}/library/{entry.id} and restores it on a new install, the
// same way NoteSyncService does for notes. SwiftData stays the source of
// truth. The document carries the TMDB poster path, never the image: a
// restore downloads the poster from TMDB again. Entries are never shared
// with friends. Every failure is silent: an entry that didn't reach
// Firestore keeps syncedAt == nil and syncPending retries it.
@MainActor
final class LibrarySyncService {
    static let shared = LibrarySyncService()
    private init() {}

    // Not a stored property, so nothing touches Firestore until a backup
    // really runs for a signed in account.
    private var db: Firestore { Firestore.firestore() }

    private var isRestoring = false
    private var isSyncingPending = false

    // Set while an account is being deleted, so a background backup or
    // restore can't write the library back to Firestore.
    var isSuspended = false
    // Bumped on sign out, same idea as NoteSyncService.generation.
    private var generation = 0

    func reset() {
        generation += 1
        isRestoring = false
        isSyncingPending = false
    }

    private func library(of uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("library")
    }

    // MARK: - Upload

    // Fire-and-forget upload for one just-saved or just-edited entry.
    func upload(_ entry: MediaLogEntry) {
        Task { try? await uploadEntry(entry) }
    }

    // Only the signed in account's own store is ever backed up, so an
    // entry from a previous account can't land under the new uid.
    private func uploadEntry(_ entry: MediaLogEntry) async throws {
        guard !isSuspended, let context = entry.modelContext,
              let uid = Auth.auth().currentUser?.uid,
              StoreManager.shared.owns(context, uid: uid) else { return }
        let entryID = entry.id.uuidString
        guard !AccountDefaults.pendingLibraryDeletions(uid: uid).contains(entryID) else { return }

        let data = entryData(for: entry)
        let reference = library(of: uid).document(entryID)
        try await reference.setData(data)

        // Deleted while the upload was in flight: take the document back out.
        guard !entry.isDeleted, entry.modelContext != nil else {
            try? await reference.delete()
            return
        }
        // Edited while the upload was in flight: leave it pending.
        guard NSDictionary(dictionary: data).isEqual(to: entryData(for: entry)) else { return }
        entry.syncedAt = Date()
        try? entry.modelContext?.save()
    }

    // The document carries tmdbID, mediaType, title, rating and loggedAt,
    // plus year, posterPath, reviewText and noteID when there are any.
    // setData replaces the whole document, so a cleared review or a
    // detached note simply has no field. noteID is the note's id, so a
    // restore can link the entry back to it.
    private func entryData(for entry: MediaLogEntry) -> [String: Any] {
        var data: [String: Any] = [
            "tmdbID": entry.tmdbID,
            "mediaType": entry.mediaType,
            "title": entry.title,
            "rating": entry.rating,
            "loggedAt": Timestamp(date: entry.loggedAt),
        ]
        if let year = entry.releaseYear { data["year"] = year }
        if let posterPath = entry.posterPath { data["posterPath"] = posterPath }
        if let review = entry.reviewText, !review.isEmpty {
            data["reviewText"] = String(review.prefix(MediaLogEntry.reviewLimit))
        }
        if let noteID = entry.note?.id.uuidString { data["noteID"] = noteID }
        return data
    }

    // MARK: - Delete

    // Called after an entry was deleted locally. The id goes on this
    // account's pending list first, so a failed cloud delete can never
    // bring the entry back, then the document is removed.
    func entryDeleted(id entryID: String, context: ModelContext) {
        guard let uid = Auth.auth().currentUser?.uid,
              StoreManager.shared.owns(context, uid: uid) else { return }
        AccountDefaults.addPendingLibraryDeletion(entryID, uid: uid)
        Task { await deleteRemote(entryID: entryID, uid: uid) }
    }

    private func deleteRemote(entryID: String, uid: String) async {
        guard !isSuspended else { return }
        do {
            try await library(of: uid).document(entryID).delete()
            AccountDefaults.removePendingLibraryDeletion(entryID, uid: uid)
        } catch {
        }
    }

    // MARK: - Sync pending

    // Retries cloud deletes, uploads every entry that isn't backed up yet
    // (which also backs up entries logged before this feature existed),
    // and downloads posters that are still missing.
    func syncPending(context: ModelContext) async {
        guard !isSuspended, !isSyncingPending, let uid = Auth.auth().currentUser?.uid,
              StoreManager.shared.owns(context, uid: uid) else { return }
        isSyncingPending = true
        let startedGeneration = generation
        defer { if startedGeneration == generation { isSyncingPending = false } }

        for entryID in AccountDefaults.pendingLibraryDeletions(uid: uid) {
            await deleteRemote(entryID: entryID, uid: uid)
        }

        let descriptor = FetchDescriptor<MediaLogEntry>(predicate: #Predicate { $0.syncedAt == nil })
        if let pending = try? context.fetch(descriptor) {
            for entry in pending { try? await uploadEntry(entry) }
        }

        _ = await downloadMissingPosters(context: context)
    }

    // MARK: - Restore

    // Fetches users/{uid}/library once and inserts every document that
    // isn't already a local entry, linking it to its note by noteID. Run
    // after the notes were restored. An entry whose note wasn't restored
    // yet is inserted unlinked and linked by a later run. Posters are
    // downloaded from TMDB again. Returns false when the fetch failed or
    // a poster couldn't be downloaded for lack of a connection, so the
    // caller can retry. Returns true when nothing is left to retry,
    // including when the run didn't start.
    @discardableResult
    func restore(context: ModelContext) async -> Bool {
        guard !isSuspended, !isRestoring, let uid = Auth.auth().currentUser?.uid,
              StoreManager.shared.owns(context, uid: uid) else { return true }
        isRestoring = true
        let startedGeneration = generation
        defer { if startedGeneration == generation { isRestoring = false } }

        // An entry deleted here whose cloud delete hasn't finished must
        // not come back.
        let pendingDeletions = Set(AccountDefaults.pendingLibraryDeletions(uid: uid))

        let snapshot: QuerySnapshot
        do {
            snapshot = try await library(of: uid).getDocuments()
        } catch {
            return false
        }
        // The account may have changed while the fetch ran.
        guard startedGeneration == generation, StoreManager.shared.owns(context, uid: Auth.auth().currentUser?.uid) else {
            return true
        }

        var localEntries: [String: MediaLogEntry] = [:]
        for entry in (try? context.fetch(FetchDescriptor<MediaLogEntry>())) ?? [] {
            localEntries[entry.id.uuidString] = entry
        }
        var notes: [String: Note] = [:]
        for note in (try? context.fetch(FetchDescriptor<Note>())) ?? [] {
            notes[note.id.uuidString] = note
        }

        for document in snapshot.documents {
            guard !pendingDeletions.contains(document.documentID),
                  let uuid = UUID(uuidString: document.documentID) else { continue }
            let data = document.data()
            let noteID = data["noteID"] as? String

            if let existing = localEntries[document.documentID] {
                // Link an entry whose note arrived after it. Never one that
                // was detached here and is still waiting to upload.
                if existing.syncedAt != nil, existing.note == nil, let noteID, let note = notes[noteID] {
                    existing.note = note
                }
                continue
            }

            guard let tmdbID = data["tmdbID"] as? Int,
                  let mediaType = data["mediaType"] as? String, mediaType == "movie" || mediaType == "tv",
                  let title = data["title"] as? String,
                  let rating = data["rating"] as? Int, (1...5).contains(rating),
                  let loggedAt = data["loggedAt"] as? Timestamp else { continue }

            let entry = MediaLogEntry(
                tmdbID: tmdbID,
                title: title,
                mediaType: mediaType,
                releaseYear: data["year"] as? Int,
                posterFileName: nil,
                rating: rating
            )
            entry.id = uuid
            entry.posterPath = data["posterPath"] as? String
            entry.reviewText = (data["reviewText"] as? String).map { String($0.prefix(MediaLogEntry.reviewLimit)) }
            entry.loggedAt = loggedAt.dateValue()
            entry.syncedAt = Date()
            context.insert(entry)
            if let noteID { entry.note = notes[noteID] }
        }

        try? context.save()
        return await downloadMissingPosters(context: context)
    }

    // Restore, retried a few times with a growing pause when the fetch or
    // a download fails, same as NoteSyncService.restoreWithRetry. Stops if
    // the account signs out meanwhile.
    func restoreWithRetry(context: ModelContext) async {
        let startedGeneration = generation
        let delays: [UInt64] = [2, 5, 10, 20]
        var attempt = 0
        while !(await restore(context: context)) {
            guard attempt < delays.count, startedGeneration == generation else { return }
            try? await Task.sleep(nanoseconds: delays[attempt] * 1_000_000_000)
            guard !Task.isCancelled, startedGeneration == generation else { return }
            attempt += 1
        }
    }

    // MARK: - Posters

    // Downloads the poster of every entry that has a poster path but no
    // file on disk (restored entries, or a download that failed earlier).
    // Returns false only when a download failed for lack of a connection.
    // A poster TMDB no longer serves is skipped, and tried again next time.
    private func downloadMissingPosters(context: ModelContext) async -> Bool {
        let descriptor = FetchDescriptor<MediaLogEntry>(predicate: #Predicate {
            $0.posterPath != nil && $0.posterFileName == nil
        })
        guard let entries = try? context.fetch(descriptor) else { return true }

        var offline = false
        for entry in entries {
            guard let posterPath = entry.posterPath else { continue }
            do {
                let fileName = try await TMDBService.shared.downloadPoster(path: posterPath)
                // Removed, or given a poster by someone else, while downloading.
                guard !entry.isDeleted, entry.modelContext != nil, entry.posterFileName == nil else {
                    try? FileManager.default.removeItem(at: MediaLogEntry.posterURL(fileName: fileName))
                    continue
                }
                entry.posterFileName = fileName
            } catch TMDBServiceError.noConnection {
                offline = true
            } catch {
            }
        }
        try? context.save()
        return !offline
    }
}
