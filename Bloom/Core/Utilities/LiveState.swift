import Foundation
import FirebaseAuth
import FirebaseFirestore

// Where a live Firestore listener is, shared by the Home tiles, reactions,
// comments and the activity feed so none of them can sit at "loading"
// forever: a listener that hasn't reported a snapshot or an error within
// LiveTimeout.seconds is moved to .failed and shows Retry.
enum LiveState: Equatable {
    case loading
    case loaded
    case permissionDenied
    // A query that needs a composite index that doesn't exist yet.
    case missingIndex
    // Any other error, and the timeout.
    case failed

    // Sorts a listener error into a state. Anything unrecognised is .failed.
    init(error: Error) {
        let nsError = error as NSError
        guard nsError.domain == FirestoreErrorDomain else {
            self = .failed
            return
        }
        switch nsError.code {
        case FirestoreErrorCode.permissionDenied.rawValue:
            self = .permissionDenied
        case FirestoreErrorCode.failedPrecondition.rawValue:
            self = .missingIndex
        default:
            self = .failed
        }
    }

    var isFinal: Bool { self != .loading }

    // A short line for a screen to show, nil while loading or loaded.
    var message: String? {
        switch self {
        case .loading, .loaded: return nil
        case .permissionDenied: return "You can\u{2019}t see this"
        case .missingIndex: return "Not available yet"
        case .failed: return "Couldn\u{2019}t load"
        }
    }
}

// The 8 second watchdog. start() replaces any running timer; cancel() is
// called when a snapshot or an error arrives or the listener is stopped.
@MainActor
final class LiveTimeout {
    static let seconds: Double = 8

    private var task: Task<Void, Never>?

    func start(_ onTimeout: @escaping @MainActor () -> Void) {
        cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.seconds))
            guard !Task.isCancelled else { return }
            self?.task = nil
            onTimeout()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}

// DEBUG only console trace of every listener's life: created, started,
// first snapshot or error, stopped, with its path, my uid, the owner's
// generation counter (where it has one) and the thread. Release builds
// compile these to nothing.
enum LiveLog {
    static func event(_ name: String, _ event: String, path: String, generation: Int? = nil) {
        #if DEBUG
        print("LIVE \(name) \(event) path=\(path) uid=\(Auth.auth().currentUser?.uid ?? "nil") " +
            "gen=\(generation.map(String.init) ?? "-") main=\(Thread.isMainThread)")
        #endif
    }

    static func snapshot(_ name: String, path: String, count: Int, fromCache: Bool, generation: Int? = nil) {
        #if DEBUG
        print("LIVE \(name) snapshot path=\(path) docs=\(count) fromCache=\(fromCache) " +
            "uid=\(Auth.auth().currentUser?.uid ?? "nil") gen=\(generation.map(String.init) ?? "-") main=\(Thread.isMainThread)")
        #endif
    }

    // Prints the whole error, which includes the console link Firestore
    // gives for a missing index.
    static func error(_ name: String, path: String, error: Error, generation: Int? = nil) {
        #if DEBUG
        let nsError = error as NSError
        print("LIVE \(name) ERROR path=\(path) uid=\(Auth.auth().currentUser?.uid ?? "nil") " +
            "gen=\(generation.map(String.init) ?? "-") main=\(Thread.isMainThread) " +
            "domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription) full=\(error)")
        #endif
    }
}
