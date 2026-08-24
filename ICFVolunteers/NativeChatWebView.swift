import SwiftUI
import WebKit

/// A WKWebView that stays edge-to-edge (behind the status bar / home
/// indicator) but still reports the real safe-area insets to the page.
///
/// Without this, the SwiftUI container's `ignoresSafeArea()` zeroes the
/// view's `safeAreaInsets`, so the web page's `env(safe-area-inset-top)`
/// resolves to 0 and headers/CTAs get pushed up under the notch. Reporting
/// the window's insets lets the page's own `env()`-based padding work.
final class SafeAreaAwareWebView: WKWebView {
    override var safeAreaInsets: UIEdgeInsets {
        let s = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets ?? super.safeAreaInsets
        // The native branded bar owns the top inset now; the web page must not
        // re-pad its own header. Only the bottom (home-indicator) inset matters,
        // so the web page's `env(safe-area-inset-bottom)` still drives the footer.
        return UIEdgeInsets(top: 0, left: 0, bottom: s.bottom, right: 0)
    }
}

/// SwiftUI entry point: a thin branded top bar framing the volunteer chat,
/// with a short splash overlay so the launch screen reads at a glance.
struct ChatWebViewContainer: View {
    var body: some View {
        VStack(spacing: 0) {
            BrandedBar()
            NativeChatWebView()
                .ignoresSafeArea(edges: .bottom) // reach under the home indicator
        }
        .overlay(SplashOverlay())
    }
}

/// Thin Deep-Blue bar with the ICF logo + app name. The status-bar region is
/// a transparent spacer filled by the bar background, so the logo and title
/// sit clearly BELOW the status bar (never overlapping the Dynamic Island).
private struct BrandedBar: View {
    var body: some View {
        VStack(spacing: 0) {
            // Status-bar region (transparent, painted by the bar background).
            Color.clear.frame(height: Self.topInset)
            // Content row — below the status bar, 44pt tall.
            HStack(spacing: 8) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 22)
                Text("ICF Volunteers")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.deepBlue)
        .ignoresSafeArea(edges: .top)
    }

    private static var topInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.top ?? 0
    }
}

/// Shared brand colours, matching the launch storyboard / web design tokens.
enum AppColors {
    /// Deep Blue #212251
    static let deepBlue = Color(red: 0.129, green: 0.133, blue: 0.318)
}

/// Branded splash shown for ~1.2s while the web view loads underneath, then
/// fades out. Matches the native launch screen (Deep Blue + official logo),
/// so the transition from launch to app is seamless. The real web content
/// loads beneath it, so no perceived load time is added.
private struct SplashOverlay: View {
    @State private var visible = true

    var body: some View {
        ZStack {
            // Deep Blue brand field, matching the launch storyboard.
            Color(red: 0.129, green: 0.133, blue: 0.318)
                .ignoresSafeArea()
            // Official white logo, reusing the asset already in the bundle.
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
        }
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: 0.35), value: visible)
        .task {
            // Hold the splash briefly, then fade out.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            visible = false
        }
        .allowsHitTesting(false) // never block touches once faded
    }
}

/// UIViewRepresentable wrapper around a WKWebView that:
///   - loads the volunteer-chat page,
///   - injects `window.__icfPushToken` (native → web) once a device token
///     exists, so the web app can register it with the backend,
///   - injects `window.__icfPushPayload` + reloads when a push is tapped, so
///     the web app can route to the waiting chat,
///   - receives `authState` messages (web → native) so the native app can
///     persist the Supabase token for background polling.
struct NativeChatWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SafeAreaAwareWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "nativeBridge")

        let webView = SafeAreaAwareWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        // Paint the web view's own background Deep Blue so any reserved
        // top safe-area region matches the branded bar instead of showing
        // a white gap above the page content.
        webView.isOpaque = true
        webView.backgroundColor = UIColor(AppColors.deepBlue)
        webView.scrollView.backgroundColor = UIColor(AppColors.deepBlue)
        // The branded bar owns the top, so the web view must not reserve the
        // device's top safe area — otherwise a ~62pt white band appears above
        // the page. Zero the automatic content inset outright.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero

        context.coordinator.webView = webView
        PushBridge.shared.consumer = context.coordinator

        if let url = URL(string: Config.webAppURL) {
            webView.load(URLRequest(url: url))
        }

        // Push an already-known token into a fresh web view if we have one.
        context.coordinator.setPushToken(PushHandler.shared.tokenString)
        return webView
    }

    func updateUIView(_ uiView: SafeAreaAwareWebView, context: Context) {}

    static func dismantleUIView(_ uiView: SafeAreaAwareWebView, coordinator: Coordinator) {
        if PushBridge.shared.consumer === coordinator {
            PushBridge.shared.consumer = nil
        }
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "nativeBridge")
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NativeBridgeConsumer {
        weak var webView: WKWebView?
        private var lastInjectedToken: String?

        // NativeBridgeConsumer

        func setPushToken(_ token: String?) {
            lastInjectedToken = token
            injectToken()
        }

        func openPushPayload(_ payload: [AnyHashable: Any]) {
            guard let webView else { return }
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let str = String(data: data, encoding: .utf8) else { return }
            // Surface the payload to the web app, then reload so the app's
            // router can react (e.g. jump into the waiting chat).
            let script = "window.__icfPushPayload = \(str);"
            webView.evaluateJavaScript(script) { [weak self] _, _ in
                self?.webView?.reload()
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            injectToken()
        }

        // MARK: WKScriptMessageHandler (web → native)

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "nativeBridge",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "authState":
                if let token = body["token"] as? String, !token.isEmpty {
                    TokenStore.save(token)
                } else {
                    TokenStore.clear()
                }
            default:
                break
            }
        }

        // MARK: Token injection

        private func injectToken() {
            guard let webView else { return }
            let token = lastInjectedToken ?? ""
            let value = token.isEmpty ? "null" : "\"\(token)\""
            let script = "window.__icfPushToken = \(value);"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
