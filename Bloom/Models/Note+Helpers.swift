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

    // Used by DaisyChainView and FlipbookView, both of which page through
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
}
