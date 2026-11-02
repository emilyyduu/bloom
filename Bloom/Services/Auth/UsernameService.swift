import Foundation
import FirebaseFirestore

enum UsernameError: LocalizedError {
    case taken

    var errorDescription: String? {
        switch self {
        case .taken: return "That username is taken. Try another."
        }
    }
}

// Usernames are unique through usernames/{usernameLower}, a document holding
// only uid and createdAt. A profile create or username change claims the
// reservation in the same batch as the profile write (the rules check it
// with existsAfter), and a change releases the old one in that batch too.
enum UsernameService {
    private static var db: Firestore { Firestore.firestore() }

    static func reference(for lower: String) -> DocumentReference {
        db.collection("usernames").document(lower)
    }

    // The uid holding a name, nil when it is free. Read from the server so a
    // stale cache never says a taken name is free.
    static func owner(of lower: String) async throws -> String? {
        let snapshot = try await reference(for: lower).getDocument(source: .server)
        return snapshot.exists ? snapshot.get("uid") as? String : nil
    }

    // True when nobody holds the name. Works before sign in, for Sign Up.
    static func isAvailable(_ lower: String) async throws -> Bool {
        try await owner(of: lower) == nil
    }

    // Adds the claim for `lower` to the batch. Throws .taken when someone
    // else holds it. A reservation I already hold needs no write. One left
    // behind by an account with no profile is cleared first, so it can't
    // keep a name locked forever.
    static func claim(_ lower: String, uid: String, in batch: WriteBatch) async throws {
        if let holder = try await owner(of: lower) {
            if holder == uid { return }
            guard try await isOrphaned(lower, heldBy: holder) else { throw UsernameError.taken }
        }
        batch.setData(["uid": uid, "createdAt": Date()], forDocument: reference(for: lower))
    }

    // Deletes the reservation when its holder has no profile. The claim's own
    // batch can't do it, because the rules check that the name is free before
    // the batch, so this is a separate write. Returns false if the holder is
    // real or the delete is refused, so the name stays taken.
    private static func isOrphaned(_ lower: String, heldBy holder: String) async throws -> Bool {
        let profile = try await db.collection("users").document(holder).getDocument(source: .server)
        guard !profile.exists else { return false }
        do {
            try await reference(for: lower).delete()
            return true
        } catch {
            return false
        }
    }

    // Adds the release of `lower` to the batch, only when I hold it. A name
    // never reserved (an older account) or held by someone else is left alone,
    // because the rules refuse to delete a document that isn't mine.
    static func release(_ lower: String, uid: String, in batch: WriteBatch) async throws {
        if try await owner(of: lower) == uid {
            batch.deleteDocument(reference(for: lower))
        }
    }

    // Commits a batch that claims `lower`. If the rules refuse it because
    // someone claimed the name since it was checked, that becomes .taken.
    static func commit(_ batch: WriteBatch, claiming lower: String, uid: String) async throws {
        do {
            try await batch.commit()
        } catch {
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain,
               nsError.code == FirestoreErrorCode.permissionDenied.rawValue,
               let holder = try? await owner(of: lower), holder != uid {
                throw UsernameError.taken
            }
            throw error
        }
    }
}
