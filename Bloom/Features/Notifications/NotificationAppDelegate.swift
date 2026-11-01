import UIKit
import UserNotifications
import FirebaseAuth
import FirebaseCore

// Attached in BloomApp with @UIApplicationDelegateAdaptor. It is created
// once, before any view, and the adaptor keeps it alive. Not per account.
// Firebase is configured here, in didFinishLaunching, and not in
// BloomApp.init: Firebase attaches itself to the app delegate, which does
// not exist yet while BloomApp.init runs.
@MainActor
final class NotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // False when GoogleService-Info.plist isn't in the app bundle. Firebase
    // can't be configured then, so nothing may touch Auth or Firestore and
    // BloomApp shows SetupRequiredView instead.
    static var hasFirebaseConfiguration: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if Self.hasFirebaseConfiguration {
            FirebaseApp.configure()
            #if targetEnvironment(simulator)
            // Lets Firebase's fictional test phone numbers work on the Simulator.
            Auth.auth().settings?.isAppVerificationDisabledForTesting = true
            #endif
        }
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Firebase phone sign in checks that notifications reach it by sending
    // itself a fake one through here. Without this forwarding the check fails
    // and sign in reports "notification not forwarded". Bloom doesn't use
    // remote notifications for anything else.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification notification: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // The result doesn't matter here. Asking Firebase is what answers its check.
        guard Self.hasFirebaseConfiguration else {
            completionHandler(.noData)
            return
        }
        _ = Auth.auth().canHandleNotification(notification)
        completionHandler(.noData)
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
        return isActive && notification.request.trigger is UNPushNotificationTrigger ? [] : [.banner, .sound]
    }

    // A tap on the banner. Awaited before returning, since the app may
    // have been launched in the background just to run this.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = NotificationPayload(userInfo: response.notification.request.content.userInfo)

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            // The reminder has no type, tapping it just opens Bloom.
            if let payload { await NotificationOpener.shared.open(payload) }
        default:
            // Dismissing the banner does nothing.
            break
        }
    }
}
