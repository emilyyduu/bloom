import SwiftUI
import SwiftData

/// The page-by-page view: today's notes shown one at a time, swiped
/// through horizontally like a small book.
struct FlipbookView: View {
    @Query private var todaysNotes: [Note]

    init() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        _todaysNotes = Query(
            filter: #Predicate<Note> { note in
                note.createdAt >= startOfDay && note.createdAt < endOfDay && !note.isDraft
            },
            sort: \Note.createdAt,
            order: .forward
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if todaysNotes.isEmpty {
                    ContentUnavailableView(
                        "No pages yet",
                        systemImage: "book",
                        description: Text("Notes you add today will appear here as pages.")
                    )
                } else {
                    TabView {
                        ForEach(todaysNotes) { note in
                            FlipbookPage(note: note)
                                .padding()
                        }
                    }
                    .tabViewStyle(.page)
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
            }
            .navigationTitle("Flipbook")
        }
    }
}

private struct FlipbookPage: View {
    let note: Note

    var body: some View {
        VStack(spacing: 16) {
            Text(note.createdAt, style: .time)
                .font(.headline)
                .foregroundStyle(.secondary)

            if let photo = note.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Text(note.text)
                .font(.title3)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    FlipbookView()
        .modelContainer(PreviewContainer.shared)
}
