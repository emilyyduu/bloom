import SwiftUI
import SwiftData

// Profile > Your Journals: a year, then a month, then a calendar, then a
// day shown as the chain. Drafts never appear. Years, months and days are
// only a way of grouping notes on screen, the Journal model and its
// Firestore backup stay grouped by day.
//
// This screen owns the notes query and the JournalModel every screen below
// it reads, so the grouping is built once, in one pass, and rebuilt only
// when the notes change.
struct JournalsView: View {
    @Query(filter: #Predicate<Note> { !$0.isDraft }, sort: \Note.createdAt, order: .reverse)
    private var notes: [Note]

    @StateObject private var model = JournalModel<Note>()

    var body: some View {
        JournalYearsScreen(
            title: "Your Journals",
            model: model,
            source: JournalSource<Note, NoteTimelineCard>(
                request: { note, focusComments in .mine(note, focusComments: focusComments) },
                card: { note, onComment, onTap in
                    NoteTimelineCard(note: note, onComment: onComment, onTap: onTap)
                }
            )
        )
        .onChange(of: notes, initial: true) { _, newNotes in
            model.update(items: newNotes)
        }
    }
}

#Preview {
    NavigationStack {
        JournalsView()
    }
    .modelContainer(PreviewContainer.shared)
}

#Preview("Dynamic Type - Accessibility 5") {
    NavigationStack {
        JournalsView()
    }
    .modelContainer(PreviewContainer.shared)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Landscape", traits: .landscapeLeft) {
    NavigationStack {
        JournalsView()
    }
    .modelContainer(PreviewContainer.shared)
}
