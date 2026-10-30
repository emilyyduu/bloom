import SwiftData
import Foundation

/// An in-memory SwiftData container pre-populated with a sample note, so
/// SwiftUI previews and #Preview blocks have something to show. This has
/// nothing to do with Firebase, previews of the note-taking views work
/// fully offline regardless of sign-in state.
enum PreviewContainer {
    @MainActor
    static let shared: ModelContainer = {
        let schema = StoreManager.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            fatalError("Could not create preview ModelContainer")
        }

        let journal = Journal(date: Calendar.current.startOfDay(for: Date()))
        let note = Note(text: "Walked past the jacaranda trees on the way home, the whole street was purple.")
        note.isDraft = false
        note.journal = journal
        // Pinned and shared, so Profile previews show a normal pinned card.
        note.isPinned = true
        note.pinnedAt = Date().addingTimeInterval(-3600)
        note.sharedWithFriends = true

        // Pinned but not shared, so previews also show the "Only you" card.
        let privateNote = Note(text: "A quiet note I'm keeping to myself for now.")
        privateNote.isDraft = false
        privateNote.journal = journal
        privateNote.isPinned = true
        privateNote.pinnedAt = Date()

        container.mainContext.insert(journal)
        container.mainContext.insert(note)
        container.mainContext.insert(privateNote)

        return container
    }()
}
