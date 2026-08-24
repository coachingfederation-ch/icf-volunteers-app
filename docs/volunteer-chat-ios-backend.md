# Lovable prompt — APNs (iOS) notifications for the volunteer live chat

Paste the block below into the Lovable agent for the `www.coachingfederation.ch`
project. It adds a **native iOS push channel** (Apple Push Notification service)
alongside the existing web-push channel, plus a device-token registration path
used by a WKWebView iOS wrapper. It does not change the visitor or volunteer
experience, only notification delivery.

Grounded against the current repo (verified):

- Web push already exists: `src/lib/live-chat-push.server.ts` (VAPID,
  `live_chat_push_subscriptions`, `notifyWaitingVisitor`).
- The trigger point is `startConversation()` in `src/lib/live-chat.server.ts`,
  which inserts a conversation with `status = 'waiting'` and calls
  `notifyWaitingVisitor(input.name)`.
- The volunteer console is `src/routes/_member/volunteer-chat.tsx`; it already
  imports `enablePush`/`disablePush` from `@/lib/volunteer-notifications` and
  resolves the signed-in user via `supabase.auth.getUser()`.
- Chat status model: `live_chat_conversations.status` in
  `waiting | active | closed`.
- Server-side Supabase is reached through `supabaseAdmin`
  (`@/integrations/supabase/client.server`); service-role tables grant nothing
  to `anon`/`authenticated`.

---

## Prompt (paste into Lovable)

> In the `www.coachingfederation.ch` Lovable project, add native iOS (APNs)
> push notifications to the volunteer live chat, parallel to the existing VAPID
> web push. Do not change the visitor flow or the volunteer console UX.
>
> ### 1. New table: `live_chat_apns_subscriptions`
> Columns: `user_id uuid` (references `auth.users`), `device_token text`
> (APNs device token, hex), `platform text NOT NULL DEFAULT 'ios'`,
> `created_at timestamptz NOT NULL DEFAULT now()`. Primary key
> `(user_id, device_token)`. RLS: like `live_chat_push_subscriptions`, grant
> **nothing** to `anon`/`authenticated`; grant all to `service_role`. Add a
> migration.
>
> ### 2. New module `src/lib/live-chat-apns.server.ts`
> Mirrors `live-chat-push.server.ts` but delegates the actual APNs fan-out to a
> Supabase edge function:
> - `saveApnsSubscription(userId: string, token: string): Promise<void>` —
>   `supabaseAdmin.from("live_chat_apns_subscriptions").upsert(..., { onConflict: "user_id,device_token" })`.
> - `removeApnsSubscription(userId: string, token: string): Promise<void>` —
>   delete the row.
> - `notifyWaitingVisitorApns(visitorName: string): Promise<{sent:number}>` —
>   call `supabase.functions.invoke("apns-send", { body: { visitorName } })`;
>   swallow errors (a push outage must never stop a visitor queueing, same as
>   the existing web push).
>
> ### 3. New server functions (in `src/lib/live-chat-volunteers.functions.ts`)
> So the web app can register/unregister the APNs token for the *authed* user:
> - `registerApnsDeviceToken(token: string)` — resolve the user server-side
>   (same pattern as the existing volunteer functions), call
>   `saveApnsSubscription(userId, token)`.
> - `unregisterApnsDeviceToken(token: string)` — call `removeApnsSubscription`.
> Export both as `useServerFn` so the console can call them.
>
> ### 4. Edge function `supabase/functions/apns-send/index.ts` (Deno)
> Reads the `live_chat_apns_subscriptions` table with the service-role client,
> and for each device token sends an APNs notification:
> - Connect over HTTP/2 to `api.push.apple.com` (use Deno's `fetch`).
> - Build a short-lived ES256 provider token signed with the P-256 key from the
>   `APNS_KEY` secret (PEM), claims `{ iss: <APNS_TEAM_ID>, iat: now }`, header
>   `{ alg: "ES256", kid: <APNS_KEY_ID> }`. Use
>   `crypto.subtle.importKey("pkcs8", pem, { name:"ECDSA", namedCurve:"P-256" }, false, ["sign"])`.
> - Request headers: `authorization: Bearer <providerToken>`,
>   `apns-topic: ch.coachingfederation.icf.volunteers`, `apns-priority: 10`,
>   `apns-push-type: alert`.
> - Payload:
>   `{ "aps": { "alert": { "title": "New chat waiting", "body": visitorName + " would like to talk to a volunteer." }, "sound": "default", "badge": 1 }, "action": "openWaitingChat" }`.
> - On response `400`/`410` (bad token / unregistered), delete the row; count
>   successful sends.
> - Read config from secrets: `APNS_KEY` (PEM), `APNS_KEY_ID`, `APNS_TEAM_ID`
>   (`78U79ZZ8M4`), `APNS_TOPIC` default `ch.coachingfederation.icf.volunteers`.
>   Do **not** log the key.
>
> ### 5. Wire the trigger
> In `src/lib/live-chat.server.ts` `startConversation()`, immediately after the
> existing `await notifyWaitingVisitor(input.name)` call, add a best-effort
> `notifyWaitingVisitorApns(input.name)` inside the same `try/catch` (dynamic
> import from `./live-chat-apns.server`). Now a push fires exactly when a new
> chat is waiting to be accepted, on both web-push and APNs.
>
> ### 6. Console registration (`src/routes/_member/volunteer-chat.tsx`)
> The iOS wrapper injects two globals into this page; handle both:
> - After sign-in resolves (`supabase.auth.getUser()`), if
>   `window.__icfPushToken` is a non-empty string, call
>   `registerApnsDeviceToken(window.__icfPushToken)`; re-check on focus. This
>   registers the iOS device token against the signed-in volunteer.
> - Hand the Supabase access token to the wrapper so the native app can poll
>   for waiting chats in the background: after sign-in, post
>   `{ type: "authState", token: <access_token> }` via
>   `window.webkit?.messageHandlers.nativeBridge?.postMessage(...)` (get it from
>   `supabase.auth.getSession()`). On sign-out, post `{ type: "authState",
>   token: null }` and call `unregisterApnsDeviceToken`.
> - If `window.__icfPushPayload?.action === "openWaitingChat"` on load, call
>   `loadLists()` so the waiting request is shown immediately.
> Guard every call with feature-detection so Safari (no native bridge, no
> `__icfPushToken`) is unaffected.
>
> ### 7. Secrets
> `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID` go into the Supabase project secrets
> (edge function env) and the project `.env` for local dev. They must never
> appear in the repo, in prompts, or in logs. Use a placeholder in any doc.

## Acceptance criteria

1. Creating a conversation with `status='waiting'` fires a web push **and** an
   APNs push to every subscribed iOS device, without blocking `startConversation`.
2. `registerApnsDeviceToken` stores one row per `(user_id, device_token)`, upserting
   on conflict; `unregisterApnsDeviceToken` removes it.
3. The console reads `window.__icfPushToken` and posts `authState` without erroring
   in plain Safari.
4. No real member data (names, emails, `cst_recno`) in code, migrations, or commits;
   use placeholders (`Anna Muster`, `ICF 000000`).
