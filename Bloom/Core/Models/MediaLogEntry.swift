import Foundation
import SwiftData

// A movie or TV show the user has logged with a star rating. Local first
// in SwiftData and backed up privately to users/{uid}/library/{id} by
// LibrarySyncService, never shared with friends. The backup keeps the
// TMDB poster path, not the image.
@Model
final class MediaLogEntry {
    var id: UUID
    var tmdbID: Int
    var title: String
    var mediaType: String // "movie" or "tv"
    var releaseYear: Int?
    var posterFileName: String?
    // TMDB's poster path, which the backup stores so a restore can
    // download the poster again. nil for an entry logged before backup
    // existed, or for a title with no poster. Additive, so SwiftData's
    // lightweight migration needs nothing from existing rows.
    var posterPath: String?
    // When the entry last reached Firestore. nil means not backed up yet
    // or changed since, so LibrarySyncService.syncPending uploads it.
    var syncedAt: Date?
    var rating: Int // 1 to 5
    // An optional short review, at most MediaLogEntry.reviewLimit
    // characters. Additive with a nil default, so SwiftData's
    // lightweight migration needs nothing from existing rows.
    var reviewText: String?
    var loggedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Note.mediaLogEntry)
    var note: Note?

    init(
        tmdbID: Int,
        title: String,
        mediaType: String,
        releaseYear: Int?,
        posterFileName: String?,
        rating: Int
    ) {
        self.id = UUID()
        self.tmdbID = tmdbID
        self.title = title
        self.mediaType = mediaType
        self.releaseYear = releaseYear
        self.posterFileName = posterFileName
        self.rating = rating
        self.loggedAt = Date()
    }
}
