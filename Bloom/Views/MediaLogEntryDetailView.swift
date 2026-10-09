import SwiftUI
import SwiftData

// Shown when tapping an entry in the Library grid. Lets the user
// adjust the rating or remove the entry entirely.
struct MediaLogEntryDetailView: View {
    let entry: MediaLogEntry

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Int
    @State private var isShowingDeleteConfirmation = false

    init(entry: MediaLogEntry) {
        self.entry = entry
        _rating = State(initialValue: entry.rating)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        posterImage
                            .frame(height: 220)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text(entry.title)
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        if let releaseYear = entry.releaseYear {
                            Text(String(releaseYear))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        StarRatingPicker(rating: $rating)
                            .onChange(of: rating) { _, newValue in
                                entry.rating = newValue
                                try? context.save()
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section {
                    Button("Delete Entry", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle(entry.mediaType == "movie" ? "Movie" : "TV Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete this entry?",
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    context.delete(entry)
                    try? context.save()
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let image = entry.posterImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Rectangle()
                .fill(Color(.secondarySystemBackground))
                .overlay {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
        }
    }
}

#Preview {
    MediaLogEntryDetailView(entry: MediaLogEntry(
        tmdbID: 1,
        title: "Paddington",
        mediaType: "movie",
        releaseYear: 2014,
        posterFileName: nil,
        rating: 4
    ))
    .modelContainer(PreviewContainer.shared)
}
