import Foundation
import SwiftData

// A movie or TV show the user has logged with a star rating. Unlike a
// Note, there is nothing private about where this data comes from, the
// catalogue details are fetched from TMDB, but the log entry itself
// still only lives in SwiftData, same as notes.
@Model
final class MediaLogEntry {
    var id: UUID
    var tmdbID: Int
    var title: String
    var mediaType: String // "movie" or "tv"
    var releaseYear: Int?
    var posterFileName: String?
    var rating: Int // 1 to 5
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
