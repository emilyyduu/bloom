import SwiftUI

// Checks the phone alert status when a view appears and whenever the app
// becomes active again, since it can change in iOS Settings.
private struct RefreshesNotificationPermission: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { await NotificationManager.shared.refresh() }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { await NotificationManager.shared.refresh() }
            }
    }
}

extension View {
    func refreshesNotificationPermission() -> some View {
        modifier(RefreshesNotificationPermission())
    }
}

// The top of the Notifications screen. Nothing once alerts are allowed.
struct PhoneAlertsCard: View {
    private let manager = NotificationManager.shared

    var body: some View {
        if manager.hasChecked {
            switch manager.authorizationStatus {
            case .notDetermined:
                card(
                    title: "Get alerts when Bloom is closed",
                    message: "Hear about friend requests, new notes and comments even when you are not in the app.",
                    button: "Allow"
                ) { Task { await manager.requestAuthorization() } }
            case .denied:
                card(
                    title: "Alerts are off",
                    message: "Bloom can\u{2019}t show alerts while it is closed. You can turn them on in iOS Settings.",
                    button: "Open Settings"
                ) { manager.openSettings() }
            default:
                EmptyView()
            }
        }
    }

    private func card(title: String, message: String, button: String, action: @escaping () -> Void) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: "bell.badge")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(button, action: action)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
            }
            .padding(.vertical, 4)
        }
    }
}
