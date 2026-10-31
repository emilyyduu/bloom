import Foundation
import SwiftData

// Gives every account its own SwiftData store file, so notes, journals and
// the streak computed from them can never leak from one account to the
// next on a shared device. A container is built once per uid and kept in
// memory, so the same account always gets the same container (and the
// same main context). Files live at Application Support/Bloom/<uid>.store.
// The old shared default store is never read, moved or deleted.
@MainActor
final class StoreManager {
    static let shared = StoreManager()
    private init() {}

    // The one schema every per account store uses. PreviewContainer reads
    // it too, so previews can't drift from the real app.
    static let schema = Schema([Note.self, Journal.self, MediaLogEntry.self])

    private var containers: [String: ModelContainer] = [:]

    func container(for uid: String) throws -> ModelContainer {
        if let existing = containers[uid] { return existing }

        let container: ModelContainer
        if Self.isRunningForPreviews {
            // Previews must never create or touch a store on disk.
            let configuration = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)
            container = try ModelContainer(for: Self.schema, configurations: [configuration])
        } else {
            let url = try storeURL(for: uid)
            let configuration = ModelConfiguration(schema: Self.schema, url: url)
            container = try ModelContainer(for: Self.schema, configurations: [configuration])
        }

        containers[uid] = container
        return container
    }

    // Whether this context is the main context of the signed-in
    // account's own store. Services that write to Firestore under the
    // current uid use this so a context left over from a previous
    // account (for example in a Task that outlived its view) can never
    // be uploaded under the new account.
    func owns(_ context: ModelContext, uid: String?) -> Bool {
        guard let uid, let container = containers[uid] else { return false }
        return container.mainContext === context
    }

    // Forgets the account's container and deletes its store files from disk
    // (the .store file and its -shm and -wal companions). Used when an
    // account is deleted.
    func deleteStore(for uid: String) {
        containers[uid] = nil
        guard let url = try? storeURL(for: uid) else { return }
        let folder = url.deletingLastPathComponent()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where file.hasPrefix(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }

    private func storeURL(for uid: String) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = support.appendingPathComponent("Bloom", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // A Firebase uid is already letters and numbers; this only
        // guarantees it can never become a path.
        let safeUID = String(uid.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        return folder.appendingPathComponent("\(safeUID).store")
    }

    private static var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
