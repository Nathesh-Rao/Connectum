import { useEffect, useRef, useState } from "react"
import { motion } from "motion/react"
import { useApp } from "../../app-state"
import { useMotionPrefs } from "../../motion"
import { Button } from "../Button"
import { Icon } from "../Icon"

// Rounded multiline field pinned above the tab bar. The send button morphs
// from a disabled grey disc to the orange action as text appears.
export function AiComposer() {
  const { ai, setSheet } = useApp()
  const { press } = useMotionPrefs()
  // A question handed over from another screen shows up prefilled, unsent.
  const [text, setText] = useState(ai.draft)
  const area = useRef<HTMLTextAreaElement>(null)
  useEffect(() => {
    if (!ai.draft) return
    ai.setDraft("")
    const el = area.current
    if (el) el.style.height = Math.min(el.scrollHeight, 112) + "px"
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  const busy = !!ai.active?.messages.some((m) => m.status !== "done")
  const ready = !!text.trim() && !busy

  const send = () => {
    if (!ready) return
    ai.send(text)
    setText("")
    if (area.current) area.current.style.height = ""
  }
  return (
    <div className="ai-composer">
      <div className="ai-field">
        <textarea
          ref={area}
          rows={1}
          value={text}
          placeholder="Ask openai"
          onChange={(e) => {
            setText(e.target.value)
            e.target.style.height = "auto"
            e.target.style.height = Math.min(e.target.scrollHeight, 112) + "px"
          }}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault()
              send()
            }
          }}
        />
        <div className="ai-field-row">
          <Button
            className="ai-circle"
            aria-label="Attach"
            onClick={() => setSheet("Attachments")}
          >
            <Icon name="attach" />
          </Button>
          <Button className="ai-pill" onClick={() => setSheet("AI model")}>
            {ai.model}
            <Icon name="chevron" />
          </Button>
          <motion.button
            className="ai-send"
            aria-label="Send"
            disabled={!ready}
            onClick={send}
            animate={{ scale: ready ? 1 : 0.92 }}
            whileTap={ready ? { scale: 0.92 } : undefined}
            transition={press}
          >
            <motion.span
              className="ai-send-on"
              animate={{ opacity: ready ? 1 : 0 }}
              transition={{ duration: 0.2 }}
            />
            <Icon name="arrowUp" />
          </motion.button>
        </div>
      </div>
    </div>
  )
}
