import Foundation
import UIKit

extension MediaLogEntry {
    static let postersDirectoryName = "Posters"

    var hasPoster: Bool {
        posterFileName != nil
    }

    var posterImage: UIImage? {
        guard let posterFileName else { return nil }
        let url = FileManager.documentsDirectory
            .appendingPathComponent(Self.postersDirectoryName, isDirectory: true)
            .appendingPathComponent(posterFileName)
        return UIImage(contentsOfFile: url.path)
    }
}
