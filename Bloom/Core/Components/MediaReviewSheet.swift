import SwiftUI

// A movie or show being reviewed, before it is an entry in the store.
// The composer holds one of these until the note is saved, so removing
// it before saving creates nothing. The Library and the entry detail
// edit through the same type.
struct MediaReviewDraft: Identifiable, Equatable {
    let id = UUID()
    var tmdbID: Int
    var title: String
    var mediaType: String // "movie" or "tv"
    var releaseYear: Int?
    // TMDB's poster path, used to show the poster and to download it
    // once when the entry is created. nil for an existing entry.
    var posterPath: String?
    // A poster already on disk, for an existing entry.
    var posterFileName: String?
    var rating = 0
    var reviewText = ""

    init(result: SearchResult) {
        tmdbID = result.id
        title = result.title
        mediaType = result.mediaType
        releaseYear = result.releaseYear
        posterPath = result.posterPath
    }

    init(entry: MediaLogEntry) {
        tmdbID = entry.tmdbID
        title = entry.title
        mediaType = entry.mediaType
        releaseYear = entry.releaseYear
        posterFileName = entry.posterFileName
        rating = entry.rating
        reviewText = entry.reviewText ?? ""
    }

    // Equal when nothing the person can change differs.
    static func == (lhs: MediaReviewDraft, rhs: MediaReviewDraft) -> Bool {
        lhs.tmdbID == rhs.tmdbID && lhs.rating == rhs.rating && lhs.reviewText == rhs.reviewText
    }

    var kindName: String { mediaType == "movie" ? "Movie" : "TV Show" }

    var trimmedReview: String? {
        let trimmed = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(MediaLogEntry.reviewLimit))
    }

    var firstReviewLine: String? { Self.firstLine(of: reviewText) }

    static func firstLine(of text: String?) -> String? {
        guard let text else { return nil }
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        return (line?.isEmpty ?? true) ? nil : line
    }
}

// A poster from disk if there is one, else from TMDB, else a film icon.
struct MediaPosterThumbnail: View {
    var fileName: String?
    var path: String?
    var width: CGFloat = 46
    var height: CGFloat = 69

    var body: some View {
        poster
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var poster: some View {
        if let image = MediaLogEntry.posterImage(fileName: fileName) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let path, let url = TMDBService.shared.posterURL(path: path) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Theme.Colors.surfaceMuted)
            }
        } else {
            Rectangle()
                .fill(Theme.Colors.surfaceMuted)
                .overlay { Image(systemName: "film").foregroundStyle(Theme.Colors.textSecondary) }
        }
    }
}

// The one review step, shared by the composer, the Library and the
// entry detail. Save stays disabled until a rating is chosen.
struct MediaReviewSheet: View {
    let onSave: (MediaReviewDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: MediaReviewDraft

    init(draft: MediaReviewDraft, onSave: @escaping (MediaReviewDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: Theme.Spacing.sm) {
                        MediaPosterThumbnail(
                            fileName: draft.posterFileName,
                            path: draft.posterPath,
                            width: 120,
                            height: 180
                        )
                        Text(draft.title)
                            .textStyle(.subheading)
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .textStyle(.callout)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .accessibilityElement(children: .combine)
                }

                Section {
                    StarRatingPicker(rating: $draft.rating)
                        .frame(maxWidth: .infinity)
                } header: {
                    SectionHeader("Your rating")
                }

                Section {
                    TextField("Say something about it (optional)", text: $draft.reviewText, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityLabel("Review")
                } header: {
                    SectionHeader("Review")
                } footer: {
                    Text("\(draft.reviewText.count) of \(MediaLogEntry.reviewLimit)")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityLabel("\(draft.reviewText.count) of \(MediaLogEntry.reviewLimit) characters used")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Your Review")
            .navigationBarTitleDisplayMode(.inline)
            // Cut by whole characters, so a pasted emoji is never split.
            .onChange(of: draft.reviewText) { _, newValue in
                if newValue.count > MediaLogEntry.reviewLimit {
                    draft.reviewText = String(newValue.prefix(MediaLogEntry.reviewLimit))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.rating == 0)
                }
            }
        }
    }

    private var subtitle: String {
        if let year = draft.releaseYear { return "\(draft.kindName), \(year)" }
        return draft.kindName
    }
}

// The chosen movie or show under the text in the composer, with Edit
// and Remove. Nothing is stored until the note itself is saved.
struct MediaDraftCard: View {
    let draft: MediaReviewDraft
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                MediaPosterThumbnail(fileName: draft.posterFileName, path: draft.posterPath)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(draft.title)
                        .textStyle(.callout)
                        .fontWeight(.medium)
                    StarRatingView(rating: draft.rating)
                    if let line = draft.firstReviewLine {
                        Text(line)
                            .textStyle(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: Theme.Spacing.lg) {
                Button("Edit", action: onEdit)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Edit review of \(draft.title)")
                Button("Remove", role: .destructive, action: onRemove)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Remove \(draft.title) from this note")
            }
            .buttonStyle(.borderless)
        }
    }
}

#Preview {
    MediaReviewSheet(
        draft: MediaReviewDraft(
            result: SearchResult(id: 1, title: "Paddington", mediaType: "movie", releaseYear: 2014, posterPath: nil)
        ),
        onSave: { _ in }
    )
}
