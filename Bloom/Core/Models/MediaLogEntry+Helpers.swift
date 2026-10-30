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
    // yet. The caller saves the context.
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
        context.insert(entry)
        entry.note = note

        if draft.posterFileName == nil, let posterPath = draft.posterPath {
            Task { @MainActor in
                guard let fileName = try? await TMDBService.shared.downloadPoster(path: posterPath) else { return }
                // The entry may have been removed while downloading.
                guard !entry.isDeleted, entry.modelContext != nil else {
                    try? FileManager.default.removeItem(at: posterURL(fileName: fileName))
                    return
                }
                entry.posterFileName = fileName
                try? context.save()
            }
        }
        return entry
    }

    // Applies an edited rating and review.
    func apply(_ draft: MediaReviewDraft) {
        rating = draft.rating
        reviewText = draft.trimmedReview
    }

    // Deletes the entry and its poster file. The caller saves.
    @MainActor
    func deleteCompletely(in context: ModelContext) {
        if let posterFileName {
            try? FileManager.default.removeItem(at: Self.posterURL(fileName: posterFileName))
        }
        context.delete(self)
    }

    private static func posterURL(fileName: String) -> URL {
        FileManager.documentsDirectory
            .appendingPathComponent(postersDirectoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
