import Foundation
import UIKit
import FirebaseFirestore

// Where a note's photo bytes live in the cloud. NoteSyncService and
// FriendPhotoCache only talk to this protocol, so moving to Cloud
// Storage later means writing one new type and changing `current`.
protocol PhotoStore {
    func upload(_ data: Data, ownerUID: String, noteID: String) async throws
    // nil means there is no photo stored for that note.
    func download(ownerUID: String, noteID: String) async throws -> Data?
    func delete(ownerUID: String, noteID: String) async throws
}

enum PhotoStores {
    static let current: PhotoStore = FirestorePhotoStore()
}

// users/{uid}/photos/{noteId} with exactly two fields: data and
// updatedAt. Kept out of the note document so listing notes never
// downloads photo bytes.
struct FirestorePhotoStore: PhotoStore {
    private var db: Firestore { Firestore.firestore() }

    private func document(ownerUID: String, noteID: String) -> DocumentReference {
        db.collection("users").document(ownerUID).collection("photos").document(noteID)
    }

    func upload(_ data: Data, ownerUID: String, noteID: String) async throws {
        try await document(ownerUID: ownerUID, noteID: noteID).setData([
            "data": data,
            "updatedAt": Timestamp(date: Date()),
        ])
    }

    func download(ownerUID: String, noteID: String) async throws -> Data? {
        let snapshot = try await document(ownerUID: ownerUID, noteID: noteID).getDocument()
        return snapshot.data()?["data"] as? Data
    }

    func delete(ownerUID: String, noteID: String) async throws {
        try await document(ownerUID: ownerUID, noteID: noteID).delete()
    }
}

// Turns a local photo into upload-sized JPEG bytes: long edge at most
// 1000 px, JPEG quality stepping down from 0.7 until under 700 KB, and
// if quality alone can't get there the dimensions shrink and it tries
// again. Never returns more than 800,000 bytes (a Firestore document
// is capped at 1 MiB).
enum PhotoCompressor {
    static let maxLongEdge: CGFloat = 1000
    static let targetBytes = 700_000
    static let hardLimitBytes = 800_000

    static func uploadData(from image: UIImage) -> Data? {
        var working = resized(image, longEdge: maxLongEdge)

        for _ in 0..<6 {
            var quality: CGFloat = 0.7
            while quality >= 0.2 {
                if let data = working.jpegData(compressionQuality: quality), data.count < targetBytes {
                    return data
                }
                quality -= 0.1
            }
            let currentLongEdge = max(working.size.width, working.size.height)
            working = resized(working, longEdge: currentLongEdge * 0.8)
        }

        if let data = working.jpegData(compressionQuality: 0.2), data.count <= hardLimitBytes {
            return data
        }
        return nil
    }

    private static func resized(_ image: UIImage, longEdge: CGFloat) -> UIImage {
        let currentLongEdge = max(image.size.width, image.size.height)
        guard currentLongEdge > longEdge, currentLongEdge > 0 else { return image }

        let scale = longEdge / currentLongEdge
        let newSize = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())

        // Scale 1 so the pixel size is exactly newSize, not multiplied
        // by the screen scale.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
