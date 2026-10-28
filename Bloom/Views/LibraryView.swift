import SwiftUI
import SwiftData

// The Library segment of the Journal tab: a showcase grid of every
// movie and show the user has logged.
struct LibraryView: View {
    @Query(sort: \MediaLogEntry.loggedAt, order: .reverse) private var entries: [MediaLogEntry]
    @State private var selectedEntry: MediaLogEntry?
    @ScaledMetric(relativeTo: .body) private var minimumColumnWidth: CGFloat = 110

    // Entries on a draft only appear once the note is posted.
    private var visibleEntries: [MediaLogEntry] {
        entries.filter { $0.note?.isDraft != true }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minimumColumnWidth), spacing: 16)]
    }

    var body: some View {
        Group {
            if visibleEntries.isEmpty {
                ContentUnavailableView(
                    "Nothing logged yet",
                    systemImage: "film",
                    description: Text("Movies and shows you log will show up here.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(visibleEntries) { entry in
                            Button {
                                selectedEntry = entry
                            } label: {
                                MediaLogEntryCell(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(cellLabel(for: entry))
                            .accessibilityHint("Opens details")
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

private func cellLabel(for entry: MediaLogEntry) -> String {
    var text = "\(entry.title), \(entry.rating) out of 5 stars"
    if let line = entry.reviewFirstLine { text += ". \(line)" }
    return text
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

            if let line = entry.reviewFirstLine {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
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
