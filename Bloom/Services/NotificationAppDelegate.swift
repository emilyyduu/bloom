import UIKit
import UserNotifications

// Attached in BloomApp with @UIApplicationDelegateAdaptor. It is created
// once, before any view, and the adaptor keeps it alive. Not per account.
// Launch work is only the delegate and the categories. Firebase is
// configured in BloomApp.init, which runs before this does.
@MainActor
final class NotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationCategories.register()
        return true
    }

    // The daily reminder shows as a banner even with Bloom open. Friend
    // activity shows nothing while Bloom is active, since the in-app banner
    // already says it, and a banner otherwise.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if notification.request.content.categoryIdentifier == NotificationConstants.Category.reminder {
            return [.banner, .sound]
        }
        return UIApplication.shared.applicationState == .active ? [] : [.banner, .sound]
    }

    // A tap on the banner or on one of its buttons. Everything is awaited
    // before returning, since the app may have been launched in the
    // background just to run this.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let payload = NotificationPayload(userInfo: userInfo)
        let recipientUID = userInfo[NotificationConstants.Key.recipientUID] as? String
        let userText = (response as? UNTextInputNotificationResponse)?.userText

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            // The reminder has no type, tapping it just opens Bloom.
            if let payload { await NotificationOpener.shared.open(payload) }
        case UNNotificationDismissActionIdentifier:
            break
        default:
            await NotificationActionHandler.perform(
                action: response.actionIdentifier,
                text: userText,
                payload: payload,
                recipientUID: recipientUID
            )
        }
    }
}
