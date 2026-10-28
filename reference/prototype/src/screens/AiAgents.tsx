import { AnimatePresence } from "motion/react"
import { useApp } from "../app-state"
import { AiComposer } from "../components/ai/AiComposer"
import { AiEmpty } from "../components/ai/AiEmpty"
import { AiHeader } from "../components/ai/AiHeader"
import { AiThread } from "../components/ai/AiThread"
import { Landing } from "../components/Landing"

// A ChatGPT-style window. Replies are simulated; nothing leaves the device.
export function AiAgents() {
  const { ai } = useApp()
  return (
    <Landing id="AI Agents" once>
      <AiHeader />
      <div className="ai-body">
        <AnimatePresence mode="wait">
          {ai.active ? (
            <AiThread key={ai.active.id} chat={ai.active} />
          ) : (
            <AiEmpty key="empty" />
          )}
        </AnimatePresence>
      </div>
      <AiComposer />
    </Landing>
  )
}
