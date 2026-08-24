import BackgroundTasks
import UIKit

/// BGAppRefreshTask: lets the system run the app briefly (~30s) roughly every
/// 15 minutes to check for a waiting chat and reflect it in the badge / a
/// local fallback notification. Remote APNs is the primary real-time path;
/// this is a safety net and badge refresher.
final class BackgroundRefresh {
    static let shared = BackgroundRefresh()
    private let identifier = "ch.coachingfederation.icf.volunteers.refresh"

    private init() {}

    func registerTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            self.handleRefresh(task: task as! BGAppRefreshTask)
        }
        // Keep the task armed while the app is in use.
        scheduleAppRefresh()
    }

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BGRefresh] schedule failed: \(error)")
        }
    }

    private func handleRefresh(task: BGAppRefreshTask) {
        // Re-arm for the next window.
        scheduleAppRefresh()
        task.expirationHandler = { task.setTaskCompleted(success: false) }

        ChatStatusPoller.checkForWaitingChat { waiting in
            DispatchQueue.main.async {
                if waiting {
                    UNUserNotificationCenter.current().setBadgeCount(1) { _ in }
                    LocalNotification.fireWaitingChat()
                }
                task.setTaskCompleted(success: true)
            }
        }
    }
}
