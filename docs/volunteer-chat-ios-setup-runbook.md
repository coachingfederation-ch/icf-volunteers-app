# Setup runbook — build, sign and install the ICF Volunteers iOS wrapper

These steps are the parts only you can do: they need your Apple Developer
account, a physical iPhone, and Xcode. The code is already written in this
folder (`/Users/hartmuth/Documents/Hermes/icf-volunteer-ios`); this runbook
turns it into an app on a phone and validates the notification pipeline.

**Time:** a couple of hours the first time, mostly waiting on downloads and
Apple's provisioning. Later builds take minutes.

---

## 0. What you're building

`ICFVolunteers` is a native SwiftUI app wrapping the volunteer chat
(`new.coachingfederation.ch/volunteer-chat`) in a WKWebView. It:

- stays signed in (WKWebView keeps the QR/email session cookies),
- registers with Apple for remote notifications and hands the device token to
  the web app, which stores it (backend prompt in `docs/`),
- shows a banner + badge when a new chat is waiting to be accepted (APNs),
- runs a `BGAppRefreshTask` that polls Supabase in the background and re-arms
  the badge / a fallback local notification,
- routes you into the waiting chat when you tap the notification.

---

## 1. Install Xcode (required, ~7 GB)

Your Mac currently has only the Command Line Tools. Install the full Xcode from
the Mac App Store (search "Xcode"), or from
`https://developer.apple.com/download/all/`. Then:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -version   # should print a version, not the CLT error
```

Also install XcodeGen (generates the `.xcodeproj` from `project.yml`):

```bash
brew install xcodegen
```

## 2. Create the iOS App ID and APNs key (developer.apple.com)

1. **App ID** — Certificates, Identifiers & Profiles → Identifiers → `+`.
   Choose **App IDs** → App. Bundle ID:
   `ch.coachingfederation.icf.volunteers`. Tick **Push Notifications**.
2. **APNs Auth Key** — Keys → `+`. Name it `ICF Volunteer Push`, tick **Apple
   Push Notifications service (APNs)**. Download the `.p8` **once** (you can't
   re-download). Note the **Key ID** and your **Team ID** (`78U79ZZ8M4`).
3. Keep the `.p8` file safe; you'll paste its contents into the Supabase secret
   `APNS_KEY` (per the backend prompt). Never put it in git or the chat.

## 3. Set the two values you must know

Open `ICFVolunteers/Config.swift` and fill in:

```swift
static let supabaseURL    = "https://<project-ref>.supabase.co"   // public
static let supabaseAnonKey = "<anon key>"                          // public
```

Both are public and ship in the web app — get them from the Lovable/Supabase
project settings (Settings → API). They power the background-refresh poller.

## 4. Generate the Xcode project and open it

```bash
cd /Users/hartmuth/Documents/Hermes/icf-volunteer-ios
xcodegen generate
open ICFVolunteers.xcodeproj
```

In Xcode: the project already sets `DEVELOPMENT_TEAM` to `78U79ZZ8M4` and uses
automatic signing. If Xcode asks you to select a team, pick the one ending in
`78U79ZZ8M4`.

## 5. Deploy the backend first

Paste the prompt from `docs/volunteer-chat-ios-backend.md` into Lovable, then
add the edge-function secrets (`APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`) in
Supabase. Without this, the app works but notifications won't arrive. You can
build the app first and add the backend after — just know pushes need it.

## 6. Run on a physical iPhone (notifications don't work in the simulator)

1. Plug in an iPhone, or choose it under the device dropdown.
2. Sign the app: Signing & Capabilities → Team `78U79ZZ8M4`. Xcode will create
   a development provisioning profile with the Push capability automatically.
3. Press **Run**. Grant notification permission when the app asks on first
   launch.

## 7. Verify the full loop

1. Open the app → sign in (QR or email) → go **online** as a volunteer. The
   web console will register the device token.
2. From another device, open the public site's live chat widget and start a
   conversation (enter a name + message).
3. Expect a push on the iPhone: **"New chat waiting — <name> would like to talk
   to a volunteer."** Tapping it should open the app and show the waiting chat.
4. Force-quit the app, start another conversation, and confirm the push still
   arrives (APNs works even when the app is terminated).

## 8. Distribution to volunteers (pick one)

- **TestFlight (recommended for a small known group):** Archive
  (Product → Archive), upload via Organizer, add testers' emails. Note the
  `aps-environment` entitlement flips from `development` to `production` on
  archive; APNs works for TestFlight builds.
- **App Store:** requires the paid Apple Developer Program and a privacy
  declaration for push.
- **Ad Hoc:** a registered-UUID profile, installed over USB. Good for a handful
  of trusted devices, but each device must be registered first.

---

## Troubleshooting

| Symptom | Likely fix |
|---|---|
| "No Accounts / team not found" | Sign in to Xcode → Settings → Accounts with your Apple ID that owns Team `78U79ZZ8M4`. |
| Build fails on signing | Ensure the App ID exists with Push enabled and automatic signing is on. |
| Push never arrives | Backend not deployed, or the APNs secrets are missing/wrong in Supabase; verify the `.p8` Key ID + Team ID. |
| Push works only in foreground | Check the notification permission was granted, and that `UIBackgroundModes` has `remote-notification` (it does in this project). |
| Background refresh never fires | iOS schedules it opportunistically; you can't force it. Test the badge by tapping a push instead. |

## Files

- `project.yml` — XcodeGen spec (regenerates the project).
- `ICFVolunteers/` — all Swift sources, `Info.plist`, entitlements, assets.
- `docs/volunteer-chat-ios-backend.md` — the Lovable prompt for the APNs backend.

## Pitfall: the header must not slide under the notch

The web page already pads its header with `env(safe-area-inset-top)` and
`__root.tsx` sets `viewport-fit=cover`. But if the native wrapper tells the
web view its safe area is zero (e.g. a plain `WKWebView` inside a SwiftUI
container with `.ignoresSafeArea(edges: .all)`), that `env()` resolves to `0`
and the "Volunteer chat" title / "Go offline" button get pushed up under the
status bar.

Fix: use `SafeAreaAwareWebView` (in `NativeChatWebView.swift`), which stays
edge-to-edge but reports the window's real safe-area insets so the page's
`env()`-based padding works. If you ever rebuild the wrapper from scratch,
keep that class — a plain `WKWebView` reintroduces the defect.
