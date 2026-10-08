import SwiftUI

// The Library segment of the Journal tab. Movie and TV logging
// (MediaLogEntry, TMDBService) hasn't been built yet, so this is an
// honest "not yet" rather than a fake populated screen.
struct LibraryView: View {
    var body: some View {
        ContentUnavailableView(
            "Coming Soon",
            systemImage: "film",
            description: Text("Logging movies and TV shows will show up here.")
        )
    }
}

#Preview {
    LibraryView()
}
