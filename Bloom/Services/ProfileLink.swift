import Foundation
import Combine

// The link a person shares to be added: bloom://add/{uid}. It carries
// the uid rather than the username so duplicate usernames can never
// make it ambiguous. The "bloom" URL scheme itself is registered in the
// target's Info settings, not here.
enum ProfileLink {
    static let scheme = "bloom"
    static let host = "add"

    static func url(forUID uid: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/\(uid)"
        return components.url
    }

    // The uid in a bloom://add/{uid} link, or nil for anything else.
    // Only letters and numbers are accepted, which is all a Firebase
    // uid contains, so a crafted link can't point at some other
    // Firestore path.
    static func uid(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == host else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, let uid = parts.first,
              (1...128).contains(uid.count),
              uid.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return uid
    }
}

struct IncomingProfileLink: Identifiable {
    let uid: String
    var id: String { uid }
}

// Holds an opened link until the signed-in app can show it. BloomApp
// hands every URL here; if I'm signed out the link simply waits, and
// ContentView presents it as soon as it appears after sign in.
@MainActor
final class ProfileLinkCoordinator: ObservableObject {
    static let shared = ProfileLinkCoordinator()
    private init() {}

    @Published var incoming: IncomingProfileLink?

    // Drops a link that was opened but not yet shown, so it can't be
    // presented to the next account on this device.
    func reset() {
        incoming = nil
    }

    func handle(_ url: URL) {
        guard let uid = ProfileLink.uid(from: url) else { return }
        incoming = IncomingProfileLink(uid: uid)
    }
}
