import SwiftUI
import UIKit
import UserNotifications

@main
struct ICFVolunteersApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ChatWebViewContainer()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Prime remote notifications and the background-refresh task.
        PushHandler.shared.registerForRemoteNotifications()
        BackgroundRefresh.shared.registerTask()
        return true
    }

    // MARK: - APNs registration callbacks

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushHandler.shared.deviceTokenDidChange(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // No device token: web-app push registration simply won't run until a
        // token exists. Not fatal for the chat itself, only for notifications.
        print("[APNs] registration failed: \(error.localizedDescription)")
    }

    /// Silent push / background content update. Re-arms the badge from the
    /// payload if a "waiting chat" push arrives while the app is backgrounded.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        PushHandler.shared.handleRemoteNotification(userInfo)
        completionHandler(.newData)
    }
}
