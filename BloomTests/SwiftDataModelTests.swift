import Foundation
import SwiftData
import Testing
@testable import Bloom

// Every test builds its own in-memory container with the schema the app
// uses, so nothing touches Application Support.
@MainActor
@Suite("Journals, notes and pins in SwiftData")
struct SwiftDataModelTests {
    // Journal.journal(for:in:) groups by Calendar.current, so the dates here
    // are built with it too. The tests then pass in any time zone.
    let calendar = Calendar.current

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(schema: StoreManager.schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StoreManager.schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func local(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func note(_ text: String, at date: Date, draft: Bool = false, in context: ModelContext) -> Note {
        let note = Note(text: text)
        note.createdAt = date
        note.isDraft = draft
        context.insert(note)
        return note
    }

    @Test("The same day gives the same journal, whatever the time of day")
    func sameDaySameJournal() throws {
        let context = try makeContext()
        let morning = Journal.journal(for: local(14, 8), in: context)
        let night = Journal.journal(for: local(14, 23, 59), in: context)
        #expect(morning === night)
        #expect(try context.fetchCount(FetchDescriptor<Journal>()) == 1)
    }

    @Test("Another day gets a new journal")
    func otherDayNewJournal() throws {
        let context = try makeContext()
        let first = Journal.journal(for: local(14), in: context)
        let second = Journal.journal(for: local(15), in: context)
        #expect(first !== second)
        #expect(first.id != second.id)
        #expect(try context.fetchCount(FetchDescriptor<Journal>()) == 2)
    }

    @Test("A journal's date is the start of its day")
    func journalDate() throws {
        let context = try makeContext()
        let journal = Journal.journal(for: local(14, 17, 45), in: context)
        #expect(journal.date == calendar.startOfDay(for: local(14)))
    }

    @Test("Sorted notes leave out drafts and run oldest first")
    func sortedNotes() throws {
        let context = try makeContext()
        let journal = Journal.journal(for: local(14), in: context)
        let evening = note("evening", at: local(14, 20), in: context)
        let draft = note("draft", at: local(14, 10), draft: true, in: context)
        let morning = note("morning", at: local(14, 7), in: context)
        let noon = note("noon", at: local(14, 12), in: context)
        for item in [evening, draft, morning, noon] { item.journal = journal }

        #expect(journal.notes.count == 4)
        #expect(journal.sortedNotes.map(\.text) == ["morning", "noon", "evening"])
    }

    @Test("A journal with no notes, or only drafts, has no sorted notes")
    func sortedNotesEmpty() throws {
        let context = try makeContext()
        let journal = Journal.journal(for: local(14), in: context)
        #expect(journal.sortedNotes.isEmpty)
        note("only a draft", at: local(14), draft: true, in: context).journal = journal
        #expect(journal.sortedNotes.isEmpty)
    }

    @Test("The pin limit is 3")
    func pinLimit() {
        #expect(Note.pinLimit == 3)
    }

    @Test("Only posted, pinned notes count towards the pin limit")
    func pinnedCount() throws {
        let context = try makeContext()
        #expect(Note.pinnedCount(in: context) == 0)

        let posted = (1...Note.pinLimit).map { note("pinned \($0)", at: local($0), in: context) }
        posted.forEach { $0.isPinned = true }
        note("not pinned", at: local(10), in: context)
        let pinnedDraft = note("pinned draft", at: local(11), draft: true, in: context)
        pinnedDraft.isPinned = true

        #expect(Note.pinnedCount(in: context) == 3)
        #expect(Note.pinnedCount(in: context) >= Note.pinLimit)
    }

    @Test("Unpinning drafts clears a pin on a draft and leaves posted pins alone")
    func unpinDrafts() throws {
        let context = try makeContext()
        let draft = note("draft", at: local(1), draft: true, in: context)
        draft.isPinned = true
        draft.pinnedAt = local(2)
        draft.syncedAt = local(2)
        let posted = note("posted", at: local(3), in: context)
        posted.isPinned = true
        posted.pinnedAt = local(4)
        posted.syncedAt = local(4)

        Note.unpinDrafts(in: context)

        #expect(!draft.isPinned)
        #expect(draft.pinnedAt == nil)
        #expect(draft.syncedAt == nil)
        #expect(posted.isPinned)
        #expect(posted.pinnedAt == local(4))
        #expect(posted.syncedAt == local(4))
    }

    @Test("A new note starts as an unshared, unpinned draft")
    func newNoteDefaults() {
        let note = Note(text: "hello")
        #expect(note.isDraft)
        #expect(!note.isPinned)
        #expect(!note.sharedWithFriends)
        #expect(note.pinnedAt == nil)
        #expect(!note.hasPhoto)
        #expect(!note.hasAudio)
    }

    @Test("Creating a draft inserts it into the context")
    func createDraft() throws {
        let context = try makeContext()
        let draft = Note.createDraft(in: context, text: "typing...")
        #expect(draft.isDraft)
        #expect(try context.fetchCount(FetchDescriptor<Note>()) == 1)
    }

    @Test("A Note counts as a journal entry only when it isn't a draft")
    func journalEntry() {
        let note = Note(text: "x")
        #expect(!note.isJournalEntry)
        note.isDraft = false
        #expect(note.isJournalEntry)
    }

    @Test("The shared schema holds notes, journals and media log entries")
    func schema() {
        let names = Set(StoreManager.schema.entities.map(\.name))
        #expect(names == ["Note", "Journal", "MediaLogEntry"])
    }

    @Test("A context that was never registered isn't owned by any account")
    func ownership() throws {
        let context = try makeContext()
        #expect(!StoreManager.shared.owns(context, uid: nil))
        #expect(!StoreManager.shared.owns(context, uid: "uid-that-has-no-container"))
    }

    @Test("The preview container is in memory with its sample notes")
    func previewContainer() throws {
        let context = PreviewContainer.shared.mainContext
        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 2)
        #expect(notes.allSatisfy { !$0.isDraft && $0.isPinned })
        #expect(notes.filter(\.sharedWithFriends).count == 1)
        #expect(try context.fetchCount(FetchDescriptor<Journal>()) == 1)
        #expect(PreviewContainer.shared.configurations.allSatisfy { $0.isStoredInMemoryOnly })
    }
}
