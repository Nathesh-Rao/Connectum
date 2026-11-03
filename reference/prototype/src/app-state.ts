import { createContext, useContext } from "react"
import type { Submission, Thread } from "./data/conversations"
import type { AiStore } from "./state/ai-store"
import type { Pin } from "./state/chat-store"

export type Screen = "Splash" | "Onboarding" | "Authentication" | "Verification" | "Enterprises" | "Chats" | "AI Agents" | "Conversation" | "Submissions" | "Submission detail" | "Profile" | "Notifications"

export interface AppState {
  screen: Screen
  go: (screen: Screen) => void
  sheet: string
  setSheet: (sheet: string) => void
  enterprise: string
  setEnterprise: (name: string) => void
  filter: string
  setFilter: (filter: string) => void
  query: string
  setQuery: (query: string) => void
  text: string
  setText: (text: string) => void
  /** Sends a text message to the open conversation. */
  sendMessage: () => void
  threads: Record<string, Thread>
  submissions: Submission[]
  selected: number
  selectSubmission: (id: number) => void
  pulses: Record<number, number>
  /** The submission being edited, or null when the form is creating one. */
  editId: number | null
  openEdit: (id: number) => void
  recentForms: string[]
  pins: Record<string, Pin>
  pinSummary: (conv: string, pin: Pin | null) => void
  formName: string | null
  openForm: (name: string) => void
  closeForm: () => void
  submitForm: (values: Record<string, string>) => void
  formsQuery: string
  setFormsQuery: (query: string) => void
  ai: AiStore
  person: string
  openChat: (name: string) => void
  step: number
  setStep: (step: number) => void
  email: string
  setEmail: (email: string) => void
}

export const AppContext = createContext<AppState | null>(null)

export function useApp() {
  const app = useContext(AppContext)
  if (!app) throw new Error("useApp must be used inside <App>")
  return app
}
