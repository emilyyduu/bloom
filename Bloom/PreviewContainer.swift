import SwiftData
import Foundation

/// An in-memory SwiftData container pre-populated with a sample note, so
/// SwiftUI previews and #Preview blocks have something to show. This has
/// nothing to do with Firebase, previews of the note-taking views work
/// fully offline regardless of sign-in state.
enum PreviewContainer {
    @MainActor
    static let shared: ModelContainer = {
        let schema = Schema([Note.self, Journal.self, MediaLogEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            fatalError("Could not create preview ModelContainer")
        }

        let journal = Journal(date: Calendar.current.startOfDay(for: Date()))
        let note = Note(text: "Walked past the jacaranda trees on the way home, the whole street was purple.")
        note.isDraft = false
        note.journal = journal

        container.mainContext.insert(journal)
        container.mainContext.insert(note)

        return container
    }()
}
