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
}

extension FileManager {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
