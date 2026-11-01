import Foundation
import Observation
import UIKit
import UserNotifications

// Whether iOS lets Bloom show alerts when it is closed. Asked in
// context (the Notifications screen or Settings), never at launch.
@MainActor
@Observable
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    // False until the first answer, so nothing flashes before it.
    private(set) var hasChecked = false

    var authorizationDescription: String {
        switch authorizationStatus {
        case .notDetermined: return "Not turned on"
        case .denied: return "Off"
        case .authorized: return "On"
        case .provisional: return "On, delivered quietly"
        case .ephemeral: return "On for now"
        @unknown default: return "Unknown"
        }
    }

    var canScheduleNotifications: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    func refresh() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        hasChecked = true
    }

    // Alert, sound and badge, the same request the daily reminder makes.
    func requestAuthorization() async {
        _ = await NotificationScheduler.shared.requestAuthorization()
        await refresh()
        NotificationBadge.shared.reapply()
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
