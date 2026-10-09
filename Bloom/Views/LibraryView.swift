import SwiftUI
import SwiftData

// The Library segment of the Journal tab: a showcase grid of every
// movie and show the user has logged.
struct LibraryView: View {
    @Query(sort: \MediaLogEntry.loggedAt, order: .reverse) private var entries: [MediaLogEntry]
    @State private var selectedEntry: MediaLogEntry?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 16)]

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Nothing logged yet",
                    systemImage: "film",
                    description: Text("Movies and shows you log will show up here.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(entries) { entry in
                            Button {
                                selectedEntry = entry
                            } label: {
                                MediaLogEntryCell(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            MediaLogEntryDetailView(entry: entry)
        }
    }
}

private struct MediaLogEntryCell: View {
    let entry: MediaLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            posterImage
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(entry.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)

            StarRatingView(rating: entry.rating)
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let image = entry.posterImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(Color(.secondarySystemBackground))
                .overlay {
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

#Preview {
    LibraryView()
        .modelContainer(PreviewContainer.shared)
}
