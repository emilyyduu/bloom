import Foundation
import UIKit
import FirebaseFirestore

// Where a profile picture's bytes live in the cloud. MyAvatar and
// AvatarCache only talk to this protocol, so moving to Cloud Storage
// later means writing one new type and changing `current`.
nonisolated protocol AvatarStore: Sendable {
    // Stores the picture and marks the profile as having one, as a
    // single atomic write. Returns the updatedAt that was written, which
    // is also what other devices key their caches on.
    func upload(_ data: Data, uid: String) async throws -> Date
    // nil means there is no picture stored for that person.
    func download(uid: String) async throws -> Data?
    // Deletes the picture and marks the profile as not having one.
    func remove(uid: String) async throws
}

enum AvatarStores {
    // Assigned once and never changed, so it can be read from any actor.
    nonisolated static let current: AvatarStore = FirestoreAvatarStore()
}

enum AvatarStoreError: Error {
    case tooLarge
}

// users/{uid}/avatar/current with exactly two fields: data and
// updatedAt. The users document carries hasAvatar and avatarUpdatedAt,
// written in the same batch, so a profile never claims a picture that
// isn't there. Kept out of the users document so listing friends never
// downloads picture bytes.
nonisolated struct FirestoreAvatarStore: AvatarStore {
    private var db: Firestore { Firestore.firestore() }

    private func userDocument(uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    private func avatarDocument(uid: String) -> DocumentReference {
        userDocument(uid: uid).collection("avatar").document("current")
    }

    func upload(_ data: Data, uid: String) async throws -> Date {
        // A last line of defence, whatever called this.
        guard data.count < AvatarProcessor.maxBytes else { throw AvatarStoreError.tooLarge }

        let now = Timestamp(date: Date())
        let batch = db.batch()
        batch.setData(["data": data, "updatedAt": now], forDocument: avatarDocument(uid: uid))
        batch.updateData(["hasAvatar": true, "avatarUpdatedAt": now], forDocument: userDocument(uid: uid))
        try await batch.commit()
        return now.dateValue()
    }

    func download(uid: String) async throws -> Data? {
        let snapshot = try await avatarDocument(uid: uid).getDocument()
        return snapshot.data()?["data"] as? Data
    }

    func remove(uid: String) async throws {
        let batch = db.batch()
        batch.deleteDocument(avatarDocument(uid: uid))
        batch.updateData(["hasAvatar": false], forDocument: userDocument(uid: uid))
        try await batch.commit()
    }
}

// Turns a picked photo into upload-sized JPEG bytes: centre cropped to
// a square, 256 by 256 pixels, JPEG quality stepping down from 0.7
// until the data is under 100,000 bytes. Returns nil rather than ever
// handing back something bigger.
enum AvatarProcessor {
    static let side: CGFloat = 256
    nonisolated static let maxBytes = 100_000

    static func uploadData(from image: UIImage) -> Data? {
        let square = croppedSquare(image)

        for step in stride(from: 7, through: 1, by: -1) {
            let quality = CGFloat(step) / 10
            if let data = square.jpegData(compressionQuality: quality), data.count < maxBytes {
                return data
            }
        }
        return nil
    }

    // Fills the square by scaling the shorter edge to `side` and
    // letting the longer edge overflow equally on both sides.
    // UIImage.draw(in:) applies the photo's orientation, so a portrait
    // phone photo isn't turned on its side.
    private static func croppedSquare(_ image: UIImage) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let scale = side / min(size.width, size.height)
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)

        // Scale 1 so the pixel size is exactly 256 by 256, and opaque
        // since JPEG has no alpha.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}
