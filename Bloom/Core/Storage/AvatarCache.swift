import Foundation
import UIKit

// Profile pictures, cached in memory and on disk. The key is the uid
// plus avatarUpdatedAt, so a changed picture is a different key and
// reloads, while an unchanged one is never downloaded twice. The disk
// copy lives in Caches as plain files, and older versions of the same
// person's picture are deleted when a newer one arrives.
actor AvatarCache {
    static let shared = AvatarCache()

    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let store: AvatarStore = AvatarStores.current

    private var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Avatars", isDirectory: true)
    }

    private func key(uid: String, updatedAt: Date?) -> String {
        let millis = Int((updatedAt?.timeIntervalSince1970 ?? 0) * 1000)
        return "\(uid)_\(millis)"
    }

    // nil means there is no picture to show, so the caller falls back
    // to initials.
    func image(uid: String, updatedAt: Date?) async -> UIImage? {
        let key = key(uid: uid, updatedAt: updatedAt)

        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }

        let fileURL = directory.appendingPathComponent("\(key).jpg")
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key as NSString)
            return image
        }

        // Many rows asking for the same person share one download.
        if let existing = inFlight[key] {
            return await existing.value
        }

        let store = store
        let task = Task<UIImage?, Never> {
            do {
                guard let data = try await store.download(uid: uid), let image = UIImage(data: data) else {
                    return nil
                }
                self.writeToDisk(data, uid: uid, key: key)
                return image
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        if let image {
            memory.setObject(image, forKey: key as NSString)
        }
        return image
    }

    // Seeds the cache with the bytes I just uploaded, so my own new
    // picture never has to be downloaded back.
    func save(_ data: Data, uid: String, updatedAt: Date) {
        let key = key(uid: uid, updatedAt: updatedAt)
        if let image = UIImage(data: data) {
            memory.setObject(image, forKey: key as NSString)
        }
        writeToDisk(data, uid: uid, key: key)
    }

    // Removes every cached picture of this person, in memory and on disk.
    func removeAll(for uid: String) {
        memory.removeAllObjects()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasPrefix("\(uid)_") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    private func writeToDisk(_ data: Data, uid: String, key: String) {
        let directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("\(key).jpg"))

        // Older versions of this person's picture are now dead weight.
        let keep = "\(key).jpg"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasPrefix("\(uid)_") && file != keep {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }
}
