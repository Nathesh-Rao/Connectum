# Push readiness

Nothing is sent and there is no Firebase dependency. The server has no `push.register` yet (`reference/notification/PUSH_AND_LOCAL_NOTIFICATIONS_PLAN.md` Part A).

## Built

| Piece | Where |
|---|---|
| `PushService` (init, requestPermission, tokenStream, onMessage, onOpened, unregister) | `lib/data/notifications/push/push_service.dart` |
| `NoopPushService`, the one in use | `.../push/noop_push_service.dart`, put in `InitialBinding` |
| `PushPayload {itemId, actionType, chatId, messageId, count}` with `tryParse` (map of strings or JSON string) and `toJson` | `.../push/push_payload.dart` |
| `PushTokenRegistry`: keeps token and permission state in `SessionStore`, clears on sign out, `session_replaced` and organisation switch (it watches `SessionStore.current`). Calls no server action | `.../push/push_token_registry.dart` |
| `NotificationRouter.resolvePayload(PushPayload)` and `handlePayload`: same destinations as a feed item, kept until sign-in and the home are ready | `lib/features/notifications/notification_router.dart` |
| Local notifications carry the same small payload, so a tap on a local notification and on a push go the same way | `lib/data/notifications/local_notification_service.dart` |

## The one place to plug FCM

1. Write `FcmPushService implements PushService` (`firebase_messaging`): token and refresh on `tokenStream`, foreground messages on `onMessage`, taps on `onOpened` (including `getInitialMessage` for a cold start). Map the data map with `PushPayload.tryParse`.
2. In `InitialBinding`, replace `NoopPushService()` with it. Nothing else changes: `PushTokenRegistry` stores the token, and screens never see the provider.
3. Wire the streams: `onOpened` -> `NotificationRouter.handlePayload`; `onMessage` -> the foreground notice (or ignore, the socket already delivers).
4. Fill the two TODO methods in `PushTokenRegistry` (`_register`, `_unregister`) with `push.register {platform, token, deviceId?, appVersion}` and `push.unregister {token}` once the server has them.

## Android pieces that will be needed

- `google-services.json` (not in the repo; owner of the Firebase project to be decided, open question 1 and 5 of the plan) and the `com.google.gms.google-services` Gradle plugin.
- `POST_NOTIFICATIONS`: already declared; the runtime prompt and its explainer sheet already exist.
- A top-level, `@pragma('vm:entry-point')` background handler for **data-only** messages. The end-to-end rule: a push for an encrypted message carries no text (plan B3). The handler wakes the app, reads the item, opens the envelope on the device (`FeedRepository.readableText` path, i.e. `E2eRepository.open`), and shows a local notification with `LocalNotificationService.show`. This needs the background isolate to reach the e2e keys (secure storage) and the session; it is the hard part and is not built.
- Item id as the collapse key and notification id (already so for local notifications), so a push and a live local notification replace each other.
- iOS later: APNs key in Firebase, `UIBackgroundModes: remote-notification`, and a notification service extension with `mutable-content` for the e2e case.

## Rules already honoured

- No tokens, OTPs or envelopes in a notification or in the payload.
- Badge = `feed.summary.unread`; a notification is cleared when its item is read, resolved, dismissed or removed (also from another device).
- A push is a hint: after opening, the app re-reads the feed.
