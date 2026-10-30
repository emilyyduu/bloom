import Foundation
import UserNotifications

// TEMPORARY DEBUG logging for "no system banners on the simulators".
// Everything prints in DEBUG only and is a no-op in release. Delete this
// file and the NotificationLog calls (search for "NotificationLog") in the
// later cleanup. Filter the console on "[Notif]".
@MainActor
enum NotificationLog {
    #if DEBUG
    // How many times the app delegate installed itself as the center's
    // delegate, and who the delegate was when last checked.
    private(set) static var delegateSetCount = 0
    static weak var expectedDelegate: UNUserNotificationCenterDelegate?
    #endif

    static func delegateWasSet(_ delegate: UNUserNotificationCenterDelegate) {
        #if DEBUG
        delegateSetCount += 1
        expectedDelegate = delegate
        print("[Notif] delegate set by NotificationAppDelegate (times set: \(delegateSetCount))")
        #endif
    }

    // Is the center's delegate still ours? Something replacing it would
    // stop willPresent and didReceive from ever running.
    static func delegateCheck() {
        #if DEBUG
        let current = UNUserNotificationCenter.current().delegate
        let name = current.map { String(describing: type(of: $0)) } ?? "nil"
        let isOurs = current != nil && current === expectedDelegate
        print("[Notif] center delegate is \(name), still ours: \(isOurs), set \(delegateSetCount) time(s)")
        #endif
    }

    static func settings(_ settings: UNNotificationSettings) {
        #if DEBUG
        print("[Notif] authorizationStatus=\(describe(settings.authorizationStatus)) alertSetting=\(describe(settings.alertSetting)) notificationCenterSetting=\(describe(settings.notificationCenterSetting)) lockScreenSetting=\(describe(settings.lockScreenSetting)) soundSetting=\(describe(settings.soundSetting))")
        #endif
    }

    // Launch and every return to the foreground: settings, delegate and
    // the categories actually registered with the system.
    static func snapshot(_ label: String) async {
        #if DEBUG
        let center = UNUserNotificationCenter.current()
        print("[Notif] --- \(label) ---")
        settings(await center.notificationSettings())
        delegateCheck()
        let categories = await center.notificationCategories().map(\.identifier).sorted()
        print("[Notif] registered categories: \(categories)")
        let pending = await center.pendingNotificationRequests().map(\.identifier).sorted()
        let delivered = await center.deliveredNotifications().map(\.request.identifier).sorted()
        print("[Notif] pending: \(pending)")
        print("[Notif] delivered: \(delivered)")
        #endif
    }

    static func skipped(_ identifier: String, _ reason: String) {
        #if DEBUG
        print("[Notif] NOT posting \(identifier): \(reason)")
        #endif
    }

    static func added(_ request: UNNotificationRequest, error: Error?) {
        #if DEBUG
        let trigger: String
        switch request.trigger {
        case let interval as UNTimeIntervalNotificationTrigger:
            trigger = "interval \(interval.timeInterval)s repeats=\(interval.repeats) next=\(interval.nextTriggerDate().map(String.init(describing:)) ?? "nil")"
        case let calendar as UNCalendarNotificationTrigger:
            trigger = "calendar next=\(calendar.nextTriggerDate().map(String.init(describing:)) ?? "nil")"
        case nil:
            trigger = "nil (immediate)"
        default:
            trigger = String(describing: type(of: request.trigger!))
        }
        let content = request.content
        print("[Notif] add id=\(request.identifier) title=\"\(content.title)\" body=\"\(content.body)\" category=\"\(content.categoryIdentifier)\" trigger=\(trigger) error=\(error.map { "\($0)" } ?? "none")")
        if content.title.isEmpty || content.body.isEmpty { print("[Notif] WARNING: empty title or body on \(request.identifier)") }
        #endif
    }

    static func removed(_ what: String, identifiers: [String]) {
        #if DEBUG
        print("[Notif] \(what): \(identifiers)")
        #endif
    }

    static func willPresent(_ notification: UNNotification, isActive: Bool, result: UNNotificationPresentationOptions) {
        #if DEBUG
        let request = notification.request
        let trigger = request.trigger.map { String(describing: type(of: $0)) } ?? "nil"
        print("[Notif] willPresent id=\(request.identifier) trigger=\(trigger) appActive=\(isActive) -> banner=\(result.contains(.banner)) sound=\(result.contains(.sound))")
        #endif
    }

    static func didReceive(_ response: UNNotificationResponse) {
        #if DEBUG
        let request = response.notification.request
        print("[Notif] didReceive id=\(request.identifier) action=\(response.actionIdentifier) category=\(request.content.categoryIdentifier) userInfo=\(request.content.userInfo)")
        #endif
    }

    #if DEBUG
    private static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }

    private static func describe(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .notSupported: return "notSupported"
        case .disabled: return "disabled"
        case .enabled: return "enabled"
        @unknown default: return "unknown"
        }
    }
    #endif
}
