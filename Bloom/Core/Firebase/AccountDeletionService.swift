import Foundation
import SwiftData
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

// Deletes the signed-in account and everything Bloom holds about it, from
// the app, in steps. The Firebase sign in is removed last, so if a step
// fails the person is still signed in and can simply try again: every step
// is safe to repeat.
//
// What it removes in Firestore:
//   what I wrote elsewhere   my comments and reactions on other people's
//                            notes, and the feed items I wrote for friends
//   friendships              every request, accepted or not, involving me
//   my notes                 each with its comments and reactions
//   my other collections     photos, voice memos, avatar, circles, library, feed
//   streaks/{uid} and users/{uid}
// Then the Firebase user, the account's store file, voice memo and photo
// files, covers, saved settings and cached pictures on this device.
//
// Limit: a reaction made before reactions carried reactorUID can't be found
// and stays on the other person's note, without a name once the profile is
// gone.
@MainActor
final class AccountDeletionService {
    static let shared = AccountDeletionService()
    private init() {}

    private let db = Firestore.firestore()
    private let pageSize = 400

    // Call after the person has reauthenticated. Throws on the first step
    // that fails.
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { throw AccountDeletionError.notSignedIn }
        let uid = user.uid
        let localFiles = noteFiles(for: uid)

        NoteSyncService.shared.isSuspended = true
        LibrarySyncService.shared.isSuspended = true
        do {
            try await eraseCloudData(uid: uid)
            try await user.delete()
        } catch {
            NoteSyncService.shared.isSuspended = false
            LibrarySyncService.shared.isSuspended = false
            throw error
        }

        // The sign in is gone and the auth listener has reset the in memory
        // state. What is left is on this device.
        await removeLocalData(uid: uid, files: localFiles)
        NoteSyncService.shared.isSuspended = false
        LibrarySyncService.shared.isSuspended = false
    }

    // MARK: - Firestore

    private func eraseCloudData(uid: String) async throws {
        // What I wrote on other people's notes and in their feeds.
        try await delete(db.collectionGroup("comments").whereField("authorUID", isEqualTo: uid))
        try await delete(db.collectionGroup("reactions").whereField("reactorUID", isEqualTo: uid))
        try await delete(db.collectionGroup("activity").whereField("fromUID", isEqualTo: uid))

        // Friend requests and friendships, in both directions.
        try await delete(db.collection("friendships").whereField("fromUID", isEqualTo: uid))
        try await delete(db.collection("friendships").whereField("toUID", isEqualTo: uid))

        // My notes, a page at a time, each with its own comments and reactions.
        let userReference = db.collection("users").document(uid)
        let notes = userReference.collection("notes")
        while true {
            let page = try await notes.limit(to: 50).getDocuments(source: .server)
            if page.documents.isEmpty { break }
            for note in page.documents {
                try await delete(note.reference.collection("comments"))
                try await delete(note.reference.collection("reactions"))
            }
            try await commitDeletes(of: page.documents.map(\.reference))
        }

        for name in ["photos", "audio", "avatar", "circles", "library", "activity"] {
            try await delete(userReference.collection(name))
        }
        try await db.collection("streaks").document(uid).delete()
        // The profile goes last. While it exists, a retry still finds its way.
        try await userReference.delete()
    }

    // Deletes every document a query or collection returns, a page at a time.
    private func delete(_ query: Query) async throws {
        while true {
            let snapshot = try await query.limit(to: pageSize).getDocuments(source: .server)
            if snapshot.documents.isEmpty { return }
            try await commitDeletes(of: snapshot.documents.map(\.reference))
            if snapshot.documents.count < pageSize { return }
        }
    }

    private func commitDeletes(of references: [DocumentReference]) async throws {
        for start in stride(from: 0, to: references.count, by: pageSize) {
            let batch = db.batch()
            for reference in references[start..<min(start + pageSize, references.count)] {
                batch.deleteDocument(reference)
            }
            try await batch.commit()
        }
    }

    // MARK: - This device

    private struct NoteFiles {
        var photos: [String] = []
        var voiceMemos: [String] = []
    }

    // The file names of the account's local photos and voice memos, read
    // before its store is removed.
    private func noteFiles(for uid: String) -> NoteFiles {
        guard let container = try? StoreManager.shared.container(for: uid),
              let notes = try? container.mainContext.fetch(FetchDescriptor<Note>()) else { return NoteFiles() }
        return NoteFiles(
            photos: notes.compactMap(\.photoFileName),
            voiceMemos: notes.compactMap(\.audioFileName)
        )
    }

    private func removeLocalData(uid: String, files: NoteFiles) async {
        let manager = FileManager.default
        for name in files.photos {
            try? manager.removeItem(at: FileManager.documentsDirectory.appendingPathComponent(name))
        }
        for name in files.voiceMemos {
            try? manager.removeItem(at: FileManager.audioDirectory.appendingPathComponent(name))
        }
        try? manager.removeItem(
            at: FileManager.documentsDirectory
                .appendingPathComponent("covers", isDirectory: true)
                .appendingPathComponent(uid, isDirectory: true)
        )

        StoreManager.shared.deleteStore(for: uid)

        // Settings saved for this account, which AccountDefaults keeps under
        // keys ending in ".<uid>".
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasSuffix(".\(uid)") {
            defaults.removeObject(forKey: key)
        }

        await AvatarCache.shared.removeAll(for: uid)

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        NotificationBadge.shared.clear()
    }
}

enum AccountDeletionError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You are not signed in."
        }
    }
}
