import Foundation
import SwiftData

/// One per day. There is no publish time and no published/unpublished
/// state: a journal is simply whatever notes have been logged under that
/// date so far.
@Model
final class Journal {
    var id: UUID
    var date: Date

    @Relationship(deleteRule: .cascade, inverse: \Note.journal)
    var notes: [Note] = []

    init(date: Date) {
        self.id = UUID()
        self.date = date
    }
}
