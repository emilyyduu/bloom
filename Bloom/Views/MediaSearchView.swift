import SwiftUI

// Presented from the composer and the Library. Searches TMDB for movies
// and shows, then opens MediaReviewSheet for whichever result is
// tapped and hands the finished review to onChosen. Nothing is stored
// here, the caller decides what to do with it.
struct MediaSearchView: View {
    let onChosen: (MediaReviewDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedResult: SearchResult?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(results) { result in
                    Button {
                        selectedResult = result
                    } label: {
                        MediaSearchResultRow(result: result)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .overlay {
                    if isSearching {
                        ProgressView()
                    } else if let errorMessage {
                        ContentUnavailableView(
                            "Couldn't search",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage)
                        )
                    }
                }

                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .navigationTitle("Log a Movie or Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $query, prompt: "Search movies and shows")
            .onSubmit(of: .search) { search() }
            .onChange(of: query) { _, newValue in
                if newValue.isEmpty {
                    results = []
                    errorMessage = nil
                }
            }
            .sheet(item: $selectedResult) { result in
                MediaReviewSheet(draft: MediaReviewDraft(result: result)) { draft in
                    onChosen(draft)
                    dismiss()
                }
            }
        }
    }

    private func search() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        Task {
            do {
                results = try await TMDBService.shared.search(query: query)
            } catch {
                results = []
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }
}

private struct MediaSearchResultRow: View {
    let result: SearchResult

    var body: some View {
        HStack(spacing: 12) {
            posterImage
                .frame(width: 46, height: 69)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.body)

                HStack(spacing: 6) {
                    Text(result.mediaType == "movie" ? "Movie" : "TV Show")
                    if let releaseYear = result.releaseYear {
                        Text(String(releaseYear))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let posterPath = result.posterPath, let url = TMDBService.shared.posterURL(path: posterPath) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Color(.secondarySystemBackground))
            }
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
    MediaSearchView(onChosen: { _ in })
}
