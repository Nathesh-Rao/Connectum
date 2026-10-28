import { useCallback, useState, type ComponentType } from "react"
import { AppContext, type AppState, type Screen } from "./app-state"
import { Button } from "./components/Button"
import { BottomNav } from "./components/BottomNav"
import { Sheet } from "./components/Sheet"
import { FormScreen } from "./components/FormScreen"
import { ScreenStage } from "./components/ScreenStage"
import { StatusBar } from "./components/StatusBar"
import { StudioSidebar } from "./components/StudioSidebar"
import { MY_SUBMISSIONS } from "./data/forms"
import { useAiStore } from "./state/ai-store"
import { useChatStore } from "./state/chat-store"
import type { NavKind } from "./motion"
import { transitionFor } from "./navigation"
import { AiAgents } from "./screens/AiAgents"
import { Authentication } from "./screens/Authentication"
import { Chats } from "./screens/Chats"
import { Conversation } from "./screens/Conversation"
import { Enterprises } from "./screens/Enterprises"
import { Notifications } from "./screens/Notifications"
import { Onboarding } from "./screens/Onboarding"
import { Profile } from "./screens/Profile"
import { Splash } from "./screens/Splash"
import { SubmissionDetail } from "./screens/SubmissionDetail"
import { Submissions } from "./screens/Submissions"
import { Verification } from "./screens/Verification"

const screens: Record<Screen, ComponentType> = {
  Splash,
  Onboarding,
  Authentication,
  Verification,
  Enterprises,
  Chats,
  "AI Agents": AiAgents,
  Conversation,
  Submissions,
  "Submission detail": SubmissionDetail,
  Profile,
  Notifications,
}

interface Nav {
  screen: Screen
  kind: NavKind
}

export default function App() {
  const [nav, setNav] = useState<Nav>({
    screen: "Splash",
    kind: "fade",
  })
  const { screen, kind } = nav
  const go = useCallback(
    (to: Screen) =>
      setNav((prev) =>
        prev.screen === to
          ? prev
          : { screen: to, kind: transitionFor(prev.screen, to) },
      ),
    [],
  )
  const [sheet, setSheet] = useState(""),
    [enterprise, setEnterprise] = useState("Agile Labs"),
    [filter, setFilter] = useState("All"),
    [query, setQuery] = useState(""),
    [text, setText] = useState(""),
    [person, setPerson] = useState("Priya Sharma"),
    [step, setStep] = useState(0),
    [email, setEmail] = useState(""),
    [formName, setFormName] = useState<string | null>(null),
    [editId, setEditId] = useState<number | null>(null),
    [formsQuery, setFormsQuery] = useState("")
  const chat = useChatStore()
  const ai = useAiStore()
  const app: AppState = {
    screen,
    go,
    sheet,
    setSheet,
    enterprise,
    setEnterprise,
    filter,
    setFilter,
    query,
    setQuery,
    text,
    setText,
    sendMessage: () => {
      if (!text.trim()) return
      chat.sendMessage(person, text)
      setText("")
    },
    threads: chat.threads,
    submissions: chat.submissions,
    selected: chat.selected,
    selectSubmission: chat.setSelected,
    pulses: chat.pulses,
    editId,
    openEdit: (id) => {
      const target = chat.submissions.find((x) => x.id === id)
      if (!target) return
      setSheet("")
      setEditId(id)
      setFormName(target.form)
    },
    recentForms: chat.recentForms,
    pins: chat.pins,
    pinSummary: chat.pinSummary,
    formName,
    openForm: (name) => {
      setSheet("")
      if (name === MY_SUBMISSIONS) go("Submissions")
      else setFormName(name)
    },
    closeForm: () => {
      setFormName(null)
      setEditId(null)
    },
    submitForm: (values) => {
      const conv = person
      const name = formName
      const editing = editId
      setFormName(null)
      setEditId(null)
      // Let the form slide away first; then the card flies in (new) or
      // updates in place and pulses (edit).
      window.setTimeout(() => {
        if (editing !== null) chat.editSubmission(editing, values)
        else if (name) chat.addSubmission(conv, name, values)
      }, 300)
    },
    formsQuery,
    setFormsQuery,
    ai,
    person,
    openChat: (name) => {
      setPerson(name)
      setText("")
      go(name === "openai" ? "AI Agents" : "Conversation")
    },
    step,
    setStep,
    email,
    setEmail,
  }
  const Current = screens[screen]
  return (
    <AppContext.Provider value={app}>
      <div className="studio">
        <StudioSidebar />
        <div className="preview">
          <div className="preview-label">
            CONNECTUM <span>390 × 844 · LIGHT</span>
          </div>
          <main
            className={`phone ${screen === "Splash" ? "splash-phone" : ""}`}
          >
            <StatusBar />
            <ScreenStage screen={screen} kind={kind}>
              <Current />
            </ScreenStage>
            <BottomNav />
            <div className="home-indicator" />
            <FormScreen />
            <Sheet />
          </main>
          <div className="preview-footer">
            <span>ONE ACCOUNT. EVERY ENTERPRISE.</span>
            <Button onClick={() => go("Splash")}>
              Start the journey <span>↗</span>
            </Button>
          </div>
        </div>
      </div>
    </AppContext.Provider>
  )
}
