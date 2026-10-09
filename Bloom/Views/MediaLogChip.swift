import SwiftUI

// The small pill shown on a note that has a movie or show attached, in
// both the Daisy Chain and Flipbook views.
struct MediaLogChip: View {
    let entry: MediaLogEntry

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "film")
            Text(entry.title)
                .lineLimit(1)
            StarRatingView(rating: entry.rating, font: .caption2)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }
}

#Preview {
    MediaLogChip(entry: MediaLogEntry(
        tmdbID: 1,
        title: "Paddington",
        mediaType: "movie",
        releaseYear: 2014,
        posterFileName: nil,
        rating: 5
    ))
}
