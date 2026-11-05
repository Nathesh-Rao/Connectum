# Notifications: audit before the build

State of the app before the notifications work. Sources: `reference/notification/*`, `reference/task-and-action/TASKS_AND_ACTIONS_FOR_MOBILE.md` section 5, `lib/`.

| Topic | What existed |
|---|---|
| Feed unread count | `lib/data/repositories/feed_repository.dart` (permanent service, put in `InitialBinding`). Only `unread` (an `RxInt`). Read from `feed.summary` on socket online and from `counts.unread` of `feed_item` / `feed_changed` / `feed_removed`. No items, no list. Reset when the session changes. |
| Bell | `lib/features/chats/chats_view.dart` (header row): `notifications_none` icon with a plain orange dot when `feed.unread > 0`. Tap -> `ChatsController.openNotifications` -> `Get.toNamed(AppRoutes.notifications)`. |
| Notifications screen | `lib/features/notifications/` is a placeholder: empty controller, a view that shows the word "Notifications", a binding. Route `AppRoutes.notifications` already in `app_pages.dart`. |
| `sd_event` handling | `SocketService` handles only the sign-out events (`session_replaced`, `session_expired`, `connection_superseded`, `disconnected`) and forwards every event on `events` (scoped to the active org+user). Payload sits under `data`. Only `FeedRepository` reads the three feed events; nobody reads `request_*`, `task_*`, `ticket_assigned`, `submission_*`, `broadcast`. |
| Reconnect hook | `SocketService.onOnline` (stream). `FeedRepository` re-reads the count on it. No app-resume hook for the feed. `DeepLinkService` and `E2eRepository` observe `WidgetsBindingObserver`. |
| Local notification packages | None in `pubspec.yaml`. |
| Android permission | Manifest has INTERNET, CAMERA only. No POST_NOTIFICATIONS, no channels, no core-library desugaring. |
| Deep link router | `DeepLinkService` handles Connectum connect links only (QR / invite). Conversations open through `ConversationRoute.open(convId)` (`/conversation/:id`, ids `dm:<user>`, `group:<name>`). `ConversationController.openOriginal(msgId)` scrolls to a message and flashes it for 1.6 s, but only for a message already loaded. |
| Mute | `Conversation.isMuted` (SQLite column `is_muted`), set by `ConversationRepository.setMuted` (`conv.mute` / `conv.unmute`). `ConversationRepository.conversations` is the in-memory list. |
| E2E decrypt | `E2eRepository.open(text:, convId:)` returns `E2eReading` (ok / cantDecrypt / pending). Used by `MessageRepository` and `ConversationRepository`. |
| Notices | `AppNotices` (light notice card, works without a context). |
| Strings | No single strings file. Text lives next to its feature; the shared pattern is a `*Texts` class (e.g. `E2eTexts`). Notifications use `NotificationTexts`. |
| Open-settings helper | `AppSettings.open()` over the `connectum/device` channel (Android and iOS). |

## Doc gaps noted while reading

- `feed.list` with `priority: all`: the docs do not say whether resolved items are included. The app fetches `resolved` on its own when the Resolved chip is chosen and merges by id, so it works either way.
- Task feed items carry no `actionType` (doc section 5): they open the detail sheet / coming-soon notice until the server sets one.
- No `since` cursor for the feed: the app re-reads state after every connect and resume.
- No `push.register` on the server yet: the token registry stores only.
