import { motion } from "motion/react"
import { useApp } from "../../app-state"
import { aiSuggestions } from "../../data/ai"
import { duration, ease, useMotionPrefs } from "../../motion"
import { Button } from "../Button"
import { Icon } from "../Icon"
import { Rise } from "../Landing"

// The empty state. Sending the first message animates it into the thread.
export function AiEmpty() {
  const { ai } = useApp()
  const { reduce } = useMotionPrefs()
  return (
    <motion.div
      className="ai-empty"
      exit={{
        opacity: 0,
        y: reduce ? 0 : -14,
        scale: reduce ? 1 : 0.98,
        transition: { duration: duration.base, ease: ease.in },
      }}
    >
      <Rise className="ai-logo" index={0}>
        <Icon name="spark" />
      </Rise>
      <Rise as="h2" index={1}>
        How can I help?
      </Rise>
      <Rise as="p" index={2}>
        Ask openai about your chats, submissions and Data Bin.
      </Rise>
      <div className="ai-suggestions">
        {aiSuggestions.map((s, i) => (
          <Button
            key={s}
            className="chip"
            landing={3 + i}
            onClick={() => ai.send(s)}
          >
            {s}
          </Button>
        ))}
      </div>
    </motion.div>
  )
}
