import SwiftUI
import SwiftData

// Shown after picking a search result: choose a rating and, optionally,
// one of today's non-draft notes to attach this log entry to. Logging
// saves the entry and downloads its poster once into Documents/Posters.
struct MediaRatingView: View {
    let result: SearchResult
    var onLogged: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(Note.todaysNotesDescriptor()) private var todaysNotes: [Note]

    @State private var rating = 0
    @State private var selectedNote: Note?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Text(result.title)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        StarRatingPicker(rating: $rating)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                if !todaysNotes.isEmpty {
                    Section {
                        Picker("Note", selection: $selectedNote) {
                            Text("None").tag(Note?.none)
                            ForEach(todaysNotes) { note in
                                Text(note.text.isEmpty ? "Untitled note" : note.text)
                                    .tag(Optional(note))
                            }
                        }
                    } header: {
                        SectionHeader("Attach to a note")
                    }
                }

                FormErrorText(message: errorMessage)
            }
            .navigationTitle("Rate It")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Log It") { save() }
                            .disabled(rating == 0)
                    }
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            var posterFileName: String?
            if let posterPath = result.posterPath {
                posterFileName = try? await TMDBService.shared.downloadPoster(path: posterPath)
            }

            let entry = MediaLogEntry(
                tmdbID: result.id,
                title: result.title,
                mediaType: result.mediaType,
                releaseYear: result.releaseYear,
                posterFileName: posterFileName,
                rating: rating
            )
            entry.note = selectedNote
            context.insert(entry)

            do {
                try context.save()
                onLogged()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

#Preview {
    MediaRatingView(
        result: SearchResult(id: 1, title: "Paddington", mediaType: "movie", releaseYear: 2014, posterPath: nil),
        onLogged: {}
    )
    .modelContainer(PreviewContainer.shared)
}
