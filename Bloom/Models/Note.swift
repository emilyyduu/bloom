import Foundation
import SwiftData

// A single journal entry: text and, optionally, a photo.
@Model
final class Note {
    var id: UUID
    var text: String
    var photoFileName: String?
    var createdAt: Date
    var isDraft: Bool

    var journal: Journal?

    init(text: String, photoFileName: String? = nil) {
        self.id = UUID()
        self.text = text
        self.photoFileName = photoFileName
        self.createdAt = Date()
        self.isDraft = true
    }
}
