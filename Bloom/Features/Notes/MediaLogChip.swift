import SwiftUI
import SwiftData

// The card shown on a note that has a movie or show attached: title,
// stars and the first line of the review. Tapping it opens the entry's
// detail.
struct MediaLogChip: View {
    let entry: MediaLogEntry
    @State private var isShowingDetail = false

    var body: some View {
        Button {
            isShowingDetail = true
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: 6) {
                    Image(systemName: "film")
                    Text(entry.title)
                        .lineLimit(2)
                }
                StarRatingView(rating: entry.rating, font: .caption2)
                if let line = entry.reviewFirstLine {
                    Text(line)
                        .textStyle(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .textStyle(.caption)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the movie or show details")
        .sheet(isPresented: $isShowingDetail) {
            MediaLogEntryDetailView(entry: entry)
        }
    }

    private var accessibilityText: String {
        var text = "\(entry.title), \(entry.rating) out of 5 stars"
        if let line = entry.reviewFirstLine { text += ". \(line)" }
        return text
    }
}

#Preview {
    MediaLogChip(entry: {
        let entry = MediaLogEntry(
            tmdbID: 1,
            title: "Paddington",
            mediaType: "movie",
            releaseYear: 2014,
            posterFileName: nil,
            rating: 5
        )
        entry.reviewText = "Warm and funny. Marmalade sandwiches forever."
        return entry
    }())
    .padding(Theme.Spacing.lg)
    .modelContainer(PreviewContainer.shared)
}
