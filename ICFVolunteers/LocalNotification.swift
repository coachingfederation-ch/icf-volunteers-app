import UserNotifications

/// Fallback local notification used by the background-refresh task when it
/// finds a waiting chat but no remote push happened to arrive.
enum LocalNotification {
    static func fireWaitingChat() {
        let content = UNMutableNotificationContent()
        content.title = "New chat waiting"
        content.body = "A volunteer chat is waiting to be accepted."
        content.sound = .default
        content.userInfo = ["action": "openWaitingChat"]

        let request = UNNotificationRequest(
            identifier: "waiting-chat-fallback",
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
}
