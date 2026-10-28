import Foundation
import SwiftData
import UIKit

extension Note {
    static func createDraft(
        in context: ModelContext,
        text: String,
        photoFileName: String? = nil
    ) -> Note {
        let note = Note(text: text, photoFileName: photoFileName)
        context.insert(note)
        return note
    }

    var hasPhoto: Bool {
        photoFileName != nil
    }

    var photo: UIImage? {
        guard let fileName = photoFileName else { return nil }
        let url = FileManager.documentsDirectory.appendingPathComponent(fileName)
        return UIImage(contentsOfFile: url.path)
    }

    static let pinLimit = 3

    // How many posted notes are pinned right now.
    static func pinnedCount(in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.isPinned && !$0.isDraft })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // Only posted notes can be pinned. If a draft somehow carries a pin,
    // this clears it and queues the note to re-upload without one.
    static func unpinDrafts(in context: ModelContext) {
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.isPinned && $0.isDraft })
        guard let drafts = try? context.fetch(descriptor), !drafts.isEmpty else { return }
        for draft in drafts {
            draft.isPinned = false
            draft.pinnedAt = nil
            draft.syncedAt = nil
        }
        try? context.save()
    }

    // Used by TodaysNotesView and HomeView, both of which page through
    // today's saved notes in creation order.
    static func todaysNotesDescriptor() -> FetchDescriptor<Note> {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        return FetchDescriptor<Note>(
            predicate: #Predicate { note in
                note.createdAt >= startOfDay && note.createdAt < endOfDay && !note.isDraft
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
    }
}

extension FileManager {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // Saves photo bytes into Documents under a fresh name and returns
    // that file name, ready to store in Note.photoFileName.
    static func writePhotoData(_ data: Data) throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        try data.write(to: documentsDirectory.appendingPathComponent(fileName))
        return fileName
    }
}
