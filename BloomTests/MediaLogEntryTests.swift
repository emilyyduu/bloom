import Foundation
import SwiftData
import Testing
@testable import Bloom

@MainActor
@Suite("Movie and show log entries")
struct MediaLogEntryTests {
    private func draft(rating: Int = 4, review: String = "") -> MediaReviewDraft {
        let result = SearchResult(id: 603, title: "The Matrix", mediaType: "movie", releaseYear: 1999, posterPath: nil)
        var draft = MediaReviewDraft(result: result)
        draft.rating = rating
        draft.reviewText = review
        return draft
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(schema: StoreManager.schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StoreManager.schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test("The review limit is 280 characters")
    func limitConstant() {
        #expect(MediaLogEntry.reviewLimit == 280)
    }

    @Test("A review at the limit is kept whole and one over is cut to the limit", arguments: [
        (279, 279), (280, 280), (281, 280), (1000, 280),
    ])
    func limit(length: Int, expectedLength: Int) throws {
        let review = draft(review: String(repeating: "a", count: length))
        #expect(try #require(review.trimmedReview).count == expectedLength)
    }

    @Test("Cutting counts whole characters, so an emoji is never split")
    func emojiNotSplit() throws {
        // A family emoji is one Character made of several scalars.
        let family = "👨‍👩‍👧"
        let text = String(repeating: "a", count: 279) + family + "tail"
        let cut = try #require(draft(review: text).trimmedReview)
        #expect(cut.count == 280)
        #expect(cut.last == Character(family))
        #expect(cut.hasSuffix(family))
    }

    @Test("A review made only of emoji is cut by emoji, not by bytes")
    func emojiOnly() throws {
        let cut = try #require(draft(review: String(repeating: "🌸", count: 300)).trimmedReview)
        #expect(cut.count == 280)
        #expect(cut == String(repeating: "🌸", count: 280))
    }

    @Test("A blank review is nil and surrounding space is trimmed", arguments: ["", "   ", "\n\n"])
    func blankReview(text: String) {
        #expect(draft(review: text).trimmedReview == nil)
    }

    @Test("Surrounding whitespace is trimmed from a review")
    func trimmed() {
        #expect(draft(review: "  Loved it \n").trimmedReview == "Loved it")
    }

    @Test("The first line stops at the first line break", arguments: [
        ("Great film\nSecond line", "Great film"),
        ("One line only", "One line only"),
        ("  padded  \nmore", "padded"),
        ("Windows\r\nbreak", "Windows"),
    ])
    func firstLine(text: String, expected: String) {
        #expect(MediaReviewDraft.firstLine(of: text) == expected)
    }

    @Test("There is no first line for nil or empty text")
    func noFirstLine() {
        #expect(MediaReviewDraft.firstLine(of: nil) == nil)
        #expect(MediaReviewDraft.firstLine(of: "") == nil)
        #expect(MediaReviewDraft.firstLine(of: "   ") == nil)
    }

    @Test("An entry made from a draft keeps the rating, trims the review and links to its note")
    func createFromDraft() throws {
        let context = try makeContext()
        let note = Note(text: "Watched it tonight")
        context.insert(note)

        let entry = MediaLogEntry.create(from: draft(rating: 5, review: "  Mind blown\nTwice  "), note: note, in: context)

        #expect(entry.rating == 5)
        #expect(entry.title == "The Matrix")
        #expect(entry.mediaType == "movie")
        #expect(entry.releaseYear == 1999)
        #expect(entry.reviewText == "Mind blown\nTwice")
        #expect(entry.reviewFirstLine == "Mind blown")
        #expect(entry.note === note)
        #expect(note.mediaLogEntry === entry)
    }

    @Test("An entry with no review has no first line")
    func entryWithoutReview() throws {
        let context = try makeContext()
        let entry = MediaLogEntry.create(from: draft(rating: 3), note: nil, in: context)
        #expect(entry.reviewText == nil)
        #expect(entry.reviewFirstLine == nil)
    }

    @Test("Editing applies the new rating and review", arguments: 1...5)
    func apply(stars: Int) throws {
        let context = try makeContext()
        let entry = MediaLogEntry.create(from: draft(rating: 1, review: "meh"), note: nil, in: context)
        var edited = MediaReviewDraft(entry: entry)
        edited.rating = stars
        edited.reviewText = "Changed my mind"
        entry.apply(edited)
        #expect(entry.rating == stars)
        #expect(entry.reviewText == "Changed my mind")
    }

    @Test("A draft starts unrated, which the review sheet won't let anyone save")
    func draftStartsUnrated() {
        #expect(draft(rating: 0).rating == 0)
        let result = SearchResult(id: 1, title: "x", mediaType: "tv", releaseYear: nil, posterPath: nil)
        #expect(MediaReviewDraft(result: result).rating == 0)
    }

    @Test("A note holds at most one entry, so a second replaces the first")
    func oneEntryPerNote() throws {
        let context = try makeContext()
        let note = Note(text: "Double feature")
        context.insert(note)
        let first = MediaLogEntry.create(from: draft(rating: 2), note: note, in: context)
        let second = MediaLogEntry.create(from: draft(rating: 5), note: note, in: context)
        #expect(note.mediaLogEntry === second)
        #expect(first.note == nil)
    }

    @Test("Kind names read Movie or TV Show")
    func kindName() {
        let movie = SearchResult(id: 1, title: "m", mediaType: "movie", releaseYear: nil, posterPath: nil)
        let show = SearchResult(id: 2, title: "s", mediaType: "tv", releaseYear: nil, posterPath: nil)
        #expect(MediaReviewDraft(result: movie).kindName == "Movie")
        #expect(MediaReviewDraft(result: show).kindName == "TV Show")
    }
}
