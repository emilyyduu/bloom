import Foundation
import SwiftData
import UIKit

extension MediaLogEntry {
    static let postersDirectoryName = "Posters"
    static let reviewLimit = 280

    var hasPoster: Bool {
        posterFileName != nil
    }

    var posterImage: UIImage? {
        Self.posterImage(fileName: posterFileName)
    }

    // Posters are read from Documents/Posters, so they show offline.
    static func posterImage(fileName: String?) -> UIImage? {
        guard let fileName else { return nil }
        let url = FileManager.documentsDirectory
            .appendingPathComponent(postersDirectoryName, isDirectory: true)
            .appendingPathComponent(fileName)
        return UIImage(contentsOfFile: url.path)
    }

    // The review up to its first line break, for chips and cards.
    var reviewFirstLine: String? {
        MediaReviewDraft.firstLine(of: reviewText)
    }

    // Creates and inserts an entry from a finished review. The poster
    // is downloaded once in the background if there isn't one on disk
    // yet, and the entry is queued for backup. The caller saves the
    // context.
    @MainActor
    static func create(from draft: MediaReviewDraft, note: Note?, in context: ModelContext) -> MediaLogEntry {
        let entry = MediaLogEntry(
            tmdbID: draft.tmdbID,
            title: draft.title,
            mediaType: draft.mediaType,
            releaseYear: draft.releaseYear,
            posterFileName: draft.posterFileName,
            rating: draft.rating
        )
        entry.reviewText = draft.trimmedReview
        entry.posterPath = draft.posterPath
        context.insert(entry)
        entry.note = note

        if draft.posterFileName == nil, let posterPath = draft.posterPath {
            Task { @MainActor in
                guard let fileName = try? await TMDBService.shared.downloadPoster(path: posterPath) else { return }
                // The entry may have been removed while downloading, or
                // given a poster meanwhile by LibrarySyncService.
                guard !entry.isDeleted, entry.modelContext != nil, entry.posterFileName == nil else {
                    try? FileManager.default.removeItem(at: posterURL(fileName: fileName))
                    return
                }
                entry.posterFileName = fileName
                try? context.save()
            }
        }
        entry.queueBackup()
        return entry
    }

    // Applies an edited rating and review, and queues the change for backup.
    @MainActor
    func apply(_ draft: MediaReviewDraft) {
        rating = draft.rating
        reviewText = draft.trimmedReview
        queueBackup()
    }

    // Marks the entry as not backed up and uploads it in the background.
    // Failures are silent: syncedAt stays nil, so syncPending retries.
    @MainActor
    func queueBackup() {
        syncedAt = nil
        LibrarySyncService.shared.upload(self)
    }

    // Deletes the entry, its poster file and its backup. The caller saves.
    @MainActor
    func deleteCompletely(in context: ModelContext) {
        if let posterFileName {
            try? FileManager.default.removeItem(at: Self.posterURL(fileName: posterFileName))
        }
        let entryID = id.uuidString
        context.delete(self)
        LibrarySyncService.shared.entryDeleted(id: entryID, context: context)
    }

    static func posterURL(fileName: String) -> URL {
        FileManager.documentsDirectory
            .appendingPathComponent(postersDirectoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
