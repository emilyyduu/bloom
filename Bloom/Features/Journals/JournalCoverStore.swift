import Foundation
import UIKit
import SwiftUI
import ImageIO
import FirebaseAuth
import Combine

// Custom journal book covers, mine only. A cover is a small JPEG at
// Documents/covers/<uid>/<key>.jpg where key is "2026" for a year and
// "2026-10" for a month. They live on this device, per account: they are
// never backed up, never uploaded and a friend never sees them. The uid is
// part of the path and of the in memory cache key, so another account
// signing in on the same device can't read these.
@MainActor
final class JournalCoverStore: ObservableObject {
    static let shared = JournalCoverStore()
    private init() {}

    enum CoverError: LocalizedError {
        case notSignedIn
        case unreadablePhoto
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in to change a cover."
            case .unreadablePhoto: return "That photo couldn\u{2019}t be read. Try a different one."
            case .saveFailed: return "The cover couldn\u{2019}t be saved on this device. Try again."
            }
        }
    }

    // Bumped whenever a cover changes, so screens showing covers refresh.
    @Published private(set) var version = 0

    // Keyed by "<uid>/<key>". A nil value means the file is missing, so a
    // default cover is shown without reading the disk again.
    private var cache: [String: UIImage?] = [:]

    static func yearKey(_ year: Int) -> String { String(year) }

    static func monthKey(_ month: JournalMonthKey) -> String {
        String(format: "%04d-%02d", month.year, month.month)
    }

    private var uid: String? { Auth.auth().currentUser?.uid }

    private func fileURL(for key: String, uid: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("covers", isDirectory: true)
            .appendingPathComponent(uid, isDirectory: true)
            .appendingPathComponent("\(key).jpg")
    }

    // The saved cover, or nil for the default one. A missing or unreadable
    // file is nil, never an error.
    func image(for key: String) -> UIImage? {
        guard let uid else { return nil }
        let cacheKey = "\(uid)/\(key)"
        if let cached = cache[cacheKey] { return cached }

        let image = (try? Data(contentsOf: fileURL(for: key, uid: uid))).flatMap { UIImage(data: $0) }
        cache[cacheKey] = image
        return image
    }

    // Crops the photo to the cover's shape, shrinks it and saves it.
    func setCover(photoData: Data, key: String) async throws {
        guard let uid else { throw CoverError.notSignedIn }
        guard let jpeg = await Task.detached(priority: .userInitiated, operation: {
            CoverImageProcessor.coverJPEG(from: photoData)
        }).value else { throw CoverError.unreadablePhoto }

        let url = fileURL(for: key, uid: uid)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try jpeg.write(to: url, options: .atomic)
        } catch {
            throw CoverError.saveFailed
        }
        cache["\(uid)/\(key)"] = UIImage(data: jpeg)
        version += 1
    }

    func removeCover(key: String) throws {
        guard let uid else { throw CoverError.notSignedIn }
        let url = fileURL(for: key, uid: uid)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw CoverError.saveFailed
            }
        }
        cache["\(uid)/\(key)"] = .some(nil)
        version += 1
    }

    // The colour a book uses: the one picked for it, or the automatic one
    // for its year or month.
    func accent(for key: String, automaticIndex: Int) -> Color {
        Theme.Covers.accent(AccountDefaults.coverColorIndexes[key] ?? automaticIndex)
    }

    // The palette index picked for a book, nil for automatic.
    func pickedColorIndex(for key: String) -> Int? {
        AccountDefaults.coverColorIndexes[key]
    }

    func setColorIndex(_ index: Int?, for key: String) {
        var indexes = AccountDefaults.coverColorIndexes
        indexes[key] = index
        AccountDefaults.coverColorIndexes = indexes
        version += 1
    }

    // Called on sign out with the rest of the in memory account state. The
    // files stay on disk under their own uid.
    func reset() {
        cache = [:]
        version += 1
    }
}

// Centre crops a photo to the cover's 3 by 4 shape, shrinks it so the long
// edge is at most 600 pixels (never enlarging it) and encodes it as JPEG
// at 0.7.
enum CoverImageProcessor {
    nonisolated static let aspect: CGFloat = 3.0 / 4.0
    nonisolated static let longEdge: CGFloat = 600
    nonisolated static let quality: CGFloat = 0.7

    nonisolated static func coverJPEG(from data: Data) -> Data? {
        // A thumbnail decode keeps a huge photo from being fully decoded,
        // and applies the photo's orientation.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return nil }

        // The biggest 3 by 4 rectangle that fits, centred.
        let crop = width / height > aspect
            ? CGSize(width: height * aspect, height: height)
            : CGSize(width: width, height: width / aspect)
        let scale = min(1, longEdge / crop.height)
        let output = CGSize(width: (crop.width * scale).rounded(), height: (crop.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: output, format: format).image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(
                x: -(width - crop.width) / 2 * scale,
                y: -(height - crop.height) / 2 * scale,
                width: width * scale,
                height: height * scale
            ))
        }
        return image.jpegData(compressionQuality: quality)
    }
}
