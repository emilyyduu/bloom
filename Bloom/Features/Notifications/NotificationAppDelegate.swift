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
        NotificationLog.delegateWasSet(self)
        NotificationCategories.register()
        Task { await NotificationLog.snapshot("launch") }
        return true
    }

    // A local notification shows as a banner and plays its sound even
    // while Bloom is open, like any other app's. A remote push (the relay)
    // while Bloom is active shows nothing, so it isn't doubled up with the
    // local notification Bloom posts itself when the activity arrives.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let isActive = UIApplication.shared.applicationState == .active
        let result: UNNotificationPresentationOptions =
            isActive && notification.request.trigger is UNPushNotificationTrigger ? [] : [.banner, .sound]
        NotificationLog.willPresent(notification, isActive: isActive, result: result)
        return result
    }

    // A tap on the banner or on one of its buttons. Everything is awaited
    // before returning, since the app may have been launched in the
    // background just to run this.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        NotificationLog.didReceive(response)
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
