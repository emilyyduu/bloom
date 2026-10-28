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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "film")
                    Text(entry.title)
                        .lineLimit(2)
                }
                StarRatingView(rating: entry.rating, font: .caption2)
                if let line = entry.reviewFirstLine {
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
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
    .padding()
    .modelContainer(PreviewContainer.shared)
}
