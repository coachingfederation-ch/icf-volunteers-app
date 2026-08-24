import Foundation

/// Small decoupler so `PushHandler` (app-wide) can reach the current web view
/// without holding a strong reference to it.
final class PushBridge {
    static let shared = PushBridge()

    /// Set by the web view coordinator when it appears; cleared on disappear.
    weak var consumer: NativeBridgeConsumer?

    private init() {}

    func pushTokenDidChange(_ token: String?) {
        consumer?.setPushToken(token)
    }

    func openPushPayload(_ payload: [AnyHashable: Any]) {
        consumer?.openPushPayload(payload)
    }
}

/// Contract the native web-view coordinator implements.
protocol NativeBridgeConsumer: AnyObject {
    /// Called when the APNs device token is available/changed.
    func setPushToken(_ token: String?)

    /// Called when the user taps a push notification.
    func openPushPayload(_ payload: [AnyHashable: Any])
}
