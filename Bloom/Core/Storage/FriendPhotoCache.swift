import Foundation
import UIKit

// Photos on a friend's shared notes, cached in memory and on disk so
// the same photo is never downloaded twice. The disk copy lives in
// Caches as plain files, never in SwiftData, and the key includes the
// friend's uid so nothing can leak between friends.
actor FriendPhotoCache {
    static let shared = FriendPhotoCache()

    enum Outcome {
        case image(UIImage)
        case failed
    }

    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<Outcome, Never>] = [:]
    private let store: PhotoStore = PhotoStores.current

    private var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FriendPhotos", isDirectory: true)
    }

    func photo(ownerUID: String, noteID: String) async -> Outcome {
        let key = "\(ownerUID)_\(noteID)"

        if let cached = memory.object(forKey: key as NSString) {
            return .image(cached)
        }

        let fileURL = directory.appendingPathComponent("\(key).jpg")
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key as NSString)
            return .image(image)
        }

        // Two rows asking for the same photo share one download.
        if let existing = inFlight[key] {
            return await existing.value
        }

        let store = store
        let directory = directory
        let task = Task<Outcome, Never> {
            do {
                guard let data = try await store.download(ownerUID: ownerUID, noteID: noteID),
                      let image = UIImage(data: data) else {
                    return .failed
                }
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? data.write(to: fileURL)
                return .image(image)
            } catch {
                return .failed
            }
        }
        inFlight[key] = task
        let outcome = await task.value
        inFlight[key] = nil

        if case .image(let image) = outcome {
            memory.setObject(image, forKey: key as NSString)
        }
        return outcome
    }
}
