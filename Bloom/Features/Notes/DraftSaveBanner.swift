import SwiftUI
import Combine

// Drives the transient "Saved to Drafts" banner ContentView shows
// above the tab bar after Save as Draft. A shared singleton rather
// than a closure threaded through the composer, since the composer is
// presented from more than one place (the Add tab, Home's empty
// state) but the banner always belongs to ContentView's tab bar.
@MainActor
final class DraftSaveBanner: ObservableObject {
    static let shared = DraftSaveBanner()
    private init() {}

    @Published private(set) var isShowing = false
    private var dismissTask: Task<Void, Never>?

    func show() {
        dismissTask?.cancel()
        isShowing = true
        AccessibilityNotification.Announcement("Saved to Drafts").post()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            isShowing = false
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        isShowing = false
    }
}
