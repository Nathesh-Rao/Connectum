import type { Screen } from "./app-state"
import type { NavKind } from "./motion"

const tabs = new Set<Screen>(["Chats", "AI Agents", "Submissions", "Profile"])

// Flow depth: Splash -> Onboarding -> Authentication -> Verification ->
// Enterprises -> Chats (tabs) -> Conversation -> Submission detail.
const depth: Record<Screen, number> = {
  Splash: 0,
  Onboarding: 1,
  Authentication: 2,
  Verification: 3,
  Enterprises: 4,
  Chats: 5,
  "AI Agents": 5,
  Submissions: 5,
  Profile: 5,
  Conversation: 6,
  Notifications: 6,
  "Submission detail": 7,
}

export function transitionFor(from: Screen, to: Screen): NavKind {
  if (from === "Splash" && to === "Onboarding") return "intro"
  if (from === "Enterprises" && to === "Chats") return "enter"
  if (to === "Splash") return "fade"
  if (tabs.has(from) && tabs.has(to)) return "tab"
  if (from === "Conversation" && to === "Submissions") return "push"
  if (from === "Conversation" && to === "AI Agents") return "tab"
  if (depth[to] === depth[from]) return "fade"
  return depth[to] > depth[from] ? "push" : "pop"
}

/** Pushed screens that support the left-edge swipe-back, and where it goes. */
export const backOf: Partial<Record<Screen, Screen>> = {
  Conversation: "Chats",
  "Submission detail": "Conversation",
  Notifications: "Chats",
  Verification: "Authentication",
}
