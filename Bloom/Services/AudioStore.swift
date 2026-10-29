import Foundation
import FirebaseFirestore

// Where a note's voice memo bytes live in the cloud, same idea as
// PhotoStore. NoteSyncService and FriendAudioCache only talk to this
// protocol, so moving to Cloud Storage later is one new type and a
// change to `current`.
protocol AudioStore {
    func upload(_ data: Data, ownerUID: String, noteID: String) async throws
    // nil means there is no memo stored for that note.
    func download(ownerUID: String, noteID: String) async throws -> Data?
    func delete(ownerUID: String, noteID: String) async throws
}

enum AudioStores {
    static let current: AudioStore = FirestoreAudioStore()
}

enum AudioStoreError: Error {
    case tooLarge
}

enum AudioLimits {
    // A Firestore document is capped at 1 MiB, stay well under it.
    static let maxBytes = 800_000
    static let maxSeconds = 60
}

// users/{uid}/audio/{noteId} with exactly two fields: data and
// updatedAt. Kept out of the note document so listing notes never
// downloads audio bytes.
struct FirestoreAudioStore: AudioStore {
    private var db: Firestore { Firestore.firestore() }

    private func document(ownerUID: String, noteID: String) -> DocumentReference {
        db.collection("users").document(ownerUID).collection("audio").document(noteID)
    }

    func upload(_ data: Data, ownerUID: String, noteID: String) async throws {
        guard data.count <= AudioLimits.maxBytes else { throw AudioStoreError.tooLarge }
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

// Memos on a friend's shared notes. Nothing is fetched until the
// person taps play. The file is kept in Caches, in plain files named
// with the friend's uid, so the same memo is never downloaded twice
// and nothing can leak between friends.
actor FriendAudioCache {
    static let shared = FriendAudioCache()

    enum Outcome {
        case file(URL)
        case failed
    }

    private var inFlight: [String: Task<Outcome, Never>] = [:]
    private let store: AudioStore = AudioStores.current

    private var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FriendAudio", isDirectory: true)
    }

    func audio(ownerUID: String, noteID: String) async -> Outcome {
        let key = "\(ownerUID)_\(noteID)"
        let fileURL = directory.appendingPathComponent("\(key).m4a")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            return .file(fileURL)
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let store = store
        let directory = directory
        let task = Task<Outcome, Never> {
            do {
                guard let data = try await store.download(ownerUID: ownerUID, noteID: noteID), !data.isEmpty else {
                    #if DEBUG
                    print("FriendAudioCache: no audio data for \(key)")
                    #endif
                    return .failed
                }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: fileURL)
                return .file(fileURL)
            } catch {
                #if DEBUG
                logFirestoreError(error, while: "downloading voice memo \(key). Permission denied here means the audio rules aren't published or you're not accepted friends")
                #endif
                return .failed
            }
        }
        inFlight[key] = task
        let outcome = await task.value
        inFlight[key] = nil
        return outcome
    }
}
