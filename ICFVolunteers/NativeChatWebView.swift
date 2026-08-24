import SwiftUI
import WebKit

/// A WKWebView that fills the area below the branded bar. Because it sits
/// below the status bar, it reports a top safe-area inset of 0 (so the page's
/// env(safe-area-inset-top) resolves to 0 and it stops padding its own header)
/// and the real bottom inset (so it pads for the home indicator).
final class SafeAreaAwareWebView: WKWebView {
    override var safeAreaInsets: UIEdgeInsets {
        let s = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets ?? super.safeAreaInsets
        return UIEdgeInsets(top: 0, left: 0, bottom: s.bottom, right: 0)
    }
}

/// SwiftUI entry point: a branded header above the volunteer chat, with a
/// short splash overlay so the launch screen reads at a glance.
struct ChatWebViewContainer: View {
    var body: some View {
        VStack(spacing: 0) {
            BrandedBar()
            // Web view fills the remaining visible height below the bar.
            NativeChatWebView()
        }
        // The TOP inset must be ignored on the CONTAINER: ignoring it on the
        // child leaves the child pushed down by the status-bar inset, opening
        // a 62pt white gap between the bar and the web content (the bar's own
        // background already paints under the status bar). The BOTTOM is
        // ignored so the page reaches under the home indicator.
        .ignoresSafeArea(edges: [.top, .bottom])
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

        // The web view sits below the branded bar, but the page root uses
        // `pt-[max(1.5rem,env(safe-area-inset-top))]`. In the app, viewport-fit
        // makes env(safe-area-inset-top) resolve to the full 62pt notch, so the
        // page pads 186px and shows a white band. A one-shot WKUserScript runs
        // too early (before TanStack hydration re-renders the DOM) to persist.
        // The robust fix is applied from didFinish via evaluateJavaScript (see
        // applyWhiteBandFix), which runs after the page is ready, re-applies on
        // a MutationObserver, and is re-run on every navigation. This early
        // documentStart script just avoids the white flash on first paint.
        let script = WKUserScript(
            source: """
            (function () {
              function fix() {
                var vp = document.querySelector('meta[name="viewport"]');
                if (vp) {
                  var c = vp.getAttribute('content') || '';
                  var n = c.replace(/\\s*viewport-fit=cover\\s*,?/i, '');
                  if (n !== c) vp.setAttribute('content', n);
                }
                var root = document.querySelector('[class*="min-h-"][class*="flex-col"]');
                if (root && root.style.paddingTop !== '0px') {
                  root.style.setProperty('padding-top', '0px', 'important');
                }
              }
              fix();
              document.addEventListener('DOMContentLoaded', fix);
              setTimeout(fix, 500);
              setTimeout(fix, 1500);
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
        // The page root uses min-h-[100dvh], which over-states the visible
        // height now that the web view sits below the branded bar — the excess
        // shows the (white) page body at the top edge. Color the under-page
        // background Deep Blue so any such region blends with the bar instead
        // of showing white.
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = UIColor(AppColors.deepBlue)
        }
        webView.isOpaque = true
        webView.backgroundColor = UIColor(AppColors.deepBlue)
        webView.scrollView.backgroundColor = UIColor(AppColors.deepBlue)
        // The web view sits below the branded bar, so the page sees its own
        // safe-area insets (top 0 below the bar, real bottom for the home
        // indicator) and its 100dvh equals the visible height. No manual
        // content-inset offsets are needed.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // A touch of breathing room between the branded bar and the page
        // content (above the QR icon).
        webView.scrollView.contentInset = UIEdgeInsets(
            top: 16, left: 0, bottom: 0, right: 0)
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
            NSLog("[ICFWB] didFinish fired")
            injectToken()
            // Runs after the page (and its framework hydration) has finished
            // loading, so the root element exists and the padding fix sticks.
            applyWhiteBandFix()
        }

        /// Removes the 186px white band at the top of the web content. The
        /// band comes from the page root's `pt-[max(1.5rem,env(safe-area-inset-top))]`
        /// resolving to the full ~62pt notch inside the WKWebView (viewport-fit
        /// is set). Unlike a one-shot WKUserScript, this is driven from
        /// didFinish and re-applies via a MutationObserver plus a short-lived
        /// interval, so it survives TanStack re-renders and the app's reloads.
        /// It is re-run on every navigation (didFinish).
        private func applyWhiteBandFix() {
            guard let webView else { return }
            let js = """
            (function () {
              function fix() {
                var vp = document.querySelector('meta[name="viewport"]');
                if (vp) {
                  var c = vp.getAttribute('content') || '';
                  var n = c.replace(/\\s*viewport-fit=cover\\s*,?/i, '');
                  if (n !== c) vp.setAttribute('content', n);
                }
                var root = document.querySelector('[class*="min-h-"][class*="flex-col"]');
                if (root && root.style.paddingTop !== '0px') {
                  root.style.setProperty('padding-top', '0px', 'important');
                }
                return root ? getComputedStyle(root).paddingTop + '|bg:' + getComputedStyle(root).backgroundColor : 'NOROOT';
              }
              fix();
              // Re-apply whenever the framework rebuilds the DOM.
              window.__icfWhiteBandObserver = window.__icfWhiteBandObserver
                || new MutationObserver(function () { fix(); });
              window.__icfWhiteBandObserver.observe(document.documentElement, {
                childList: true, subtree: true, attributes: true,
                attributeFilter: ['class', 'style']
              });
              // Fallback in case the observer is throttled during hydration.
              if (!window.__icfWhiteBandTimer) {
                var tries = 0;
                window.__icfWhiteBandTimer = setInterval(function () {
                  fix();
                  if (++tries > 5) clearInterval(window.__icfWhiteBandTimer);
                }, 800);
              }
              return fix();
            })();
            """
            webView.evaluateJavaScript(js) { result, error in
                if let error = error {
                    NSLog("[ICFWB] eval error: \(error.localizedDescription)")
                } else {
                    NSLog("[ICFWB] fix result: \(String(describing: result))")
                }
            }

            // Late diagnostic + re-fix: the TanStack root may render well after
            // didFinish. Re-run the fix from Swift at later points.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak webView] in
                guard let webView else { return }
                let dbg = """
                (function () {
                  var el = document.elementFromPoint(window.innerWidth/2, 10);
                  return JSON.stringify({
                    innerH: window.innerHeight, innerW: window.innerWidth,
                    scrollY: window.scrollY,
                    scrollTop: document.scrollingElement ? document.scrollingElement.scrollTop : null,
                    docScrollH: document.documentElement.scrollHeight,
                    bodyScrollH: document.body ? document.body.scrollHeight : null,
                    topEl: el ? {tag: el.tagName, cls: String(el.className).slice(0,60)} : null
                  });
                })();
                """
                webView.evaluateJavaScript(dbg) { r, e in
                    var pageStr = "?"
                    if let r = r as? String { pageStr = r }
                    let f = webView.frame
                    let sv = webView.scrollView
                    let winFrame = webView.convert(webView.bounds, to: nil)
                    var superDesc = "nil"
                    if let sup = webView.superview {
                        let sf = sup.frame
                        superDesc = String(format: "%@ frame=%.0f,%.0f %.0fx%.0f safe=%.0f/%.0f/%.0f/%.0f", NSStringFromClass(type(of: sup)), sf.origin.x, sf.origin.y, sf.width, sf.height, sup.safeAreaInsets.top, sup.safeAreaInsets.left, sup.safeAreaInsets.bottom, sup.safeAreaInsets.right)
                    }
                    let native = String(format: "frame=%.0f,%.0f %.0fx%.0f winFrame=%.0f,%.0f %.0fx%.0f contentOffset=%.0f,%.0f contentInset=%.0f,%.0f,%.0f,%.0f contentSize=%.0fx%.0f super=%@",
                                        f.origin.x, f.origin.y, f.width, f.height,
                                        winFrame.origin.x, winFrame.origin.y, winFrame.width, winFrame.height,
                                        sv.contentOffset.x, sv.contentOffset.y,
                                        sv.contentInset.top, sv.contentInset.left,
                                        sv.contentInset.bottom, sv.contentInset.right,
                                        sv.contentSize.width, sv.contentSize.height,
                                        superDesc)
                    NSLog("[ICFWB] NATIVE(4s): \(native) | page: \(pageStr)")
                }
            }
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
