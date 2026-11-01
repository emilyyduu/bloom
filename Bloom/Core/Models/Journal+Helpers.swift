import Foundation
import SwiftData

extension Journal {
    // Finds (or creates and inserts) the journal for a given day.
    static func journal(for date: Date, in context: ModelContext) -> Journal {
        let startOfDay = Calendar.current.startOfDay(for: date)

        var descriptor = FetchDescriptor<Journal>(
            predicate: #Predicate { $0.date == startOfDay }
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let journal = Journal(date: startOfDay)
        context.insert(journal)
        return journal
    }

    var sortedNotes: [Note] {
        notes
            .filter { !$0.isDraft }
            .sorted { $0.createdAt < $1.createdAt }
    }
}
