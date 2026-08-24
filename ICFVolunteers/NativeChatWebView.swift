import SwiftUI
import WebKit

/// A WKWebView that stays edge-to-edge but reports the real safe-area insets
/// to the page, so the web app's `env(safe-area-inset-*)` padding is correct.
final class SafeAreaAwareWebView: WKWebView {
    override var safeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets ?? super.safeAreaInsets
    }
}

/// SwiftUI entry point: the volunteer chat rendered full-bleed with a small
/// branded bar overlaying the top safe-area region, plus a short splash.
struct ChatWebViewContainer: View {
    var body: some View {
        ZStack(alignment: .top) {
            // Web view fills the whole screen (edge-to-edge, under the notch).
            // The page is a full-bleed PWA and pads its own header by
            // env(safe-area-inset-top), so its top 62pt is a correct notch
            // reservation — the opaque branded bar below sits exactly on it.
            NativeChatWebView()
                .ignoresSafeArea(edges: .all)
            // Bar overlays exactly the safe-area top region the page reserves.
            BrandedBar()
        }
        .overlay(SplashOverlay())
    }
}

/// Shared app layout constants.
enum AppLayout {
    /// Height of the branded header's title row (below the status bar).
    static let headerContentHeight: CGFloat = 44
}

/// Deep-Blue branded header: a status-bar spacer plus a title row BELOW the
/// status bar, so the logo/title never collide with the clock or Dynamic
/// Island. Overlays the page's own safe-area reservation (which the page pads
/// for), so there is no seam between the bar and the content below it.
private struct BrandedBar: View {
    var body: some View {
        VStack(spacing: 0) {
            // Status-bar region — empty spacer painted by the bar background,
            // so the system clock / Dynamic Island render here cleanly.
            Color.clear.frame(height: Self.topInset)
            // Title row — sits fully below the status bar.
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
            .frame(height: AppLayout.headerContentHeight)
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

        // The native branded bar owns the top, but the page is a full-bleed PWA
        // (viewport-fit=cover) that reserves env(safe-area-inset-top) for the
        // notch. WebKit computes that from the device, not from our view, so a
        // white band appears under the bar. Paint that reserved region Deep
        // Blue (matching the bar) so there is no visible seam, and remove the
        // top safe-area offset so content sits directly under the bar.
        let script = WKUserScript(
            source: """
            (function () {
              function fix() {
                // Remove the top safe-area reservation.
                var vp = document.querySelector('meta[name="viewport"]');
                if (vp) {
                  var c = vp.getAttribute('content') || '';
                  var n = c.replace(/\\s*viewport-fit=cover\\s*,?/i, '');
                  if (n !== c) vp.setAttribute('content', n);
                }
                // Belt and braces: paint the root deep blue so any reserved
                // region blends with the branded bar (inline, highest priority).
                var html = document.documentElement;
                var body = document.body;
                html.style.setProperty('background-color', '#212251', 'important');
                html.style.setProperty('min-height', '100%', 'important');
                if (body) body.style.setProperty('background-color', '#212251', 'important');
              }
              fix();
              document.addEventListener('DOMContentLoaded', fix);
              // Also fix on React hydration (TanStack may re-render the head).
              setTimeout(fix, 1000);
              setTimeout(fix, 3000);
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)
        config.userContentController.add(context.coordinator, name: "nativeBridge")

        let webView = SafeAreaAwareWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        // Color any region under the page content (e.g. reserved safe areas)
        // Deep Blue so it blends with the branded bar instead of showing white.
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = UIColor(AppColors.deepBlue)
        }
        webView.isOpaque = true
        webView.backgroundColor = UIColor(AppColors.deepBlue)
        webView.scrollView.backgroundColor = UIColor(AppColors.deepBlue)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // The page reserves the notch (62pt) itself, but the header is that
        // 62pt PLUS a 44pt title band. Push the page content down by the extra
        // title-band height (plus a small margin) so it clears the full header.
        webView.scrollView.contentInset = UIEdgeInsets(
            top: AppLayout.headerContentHeight + 8, left: 0, bottom: 0, right: 0)
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
