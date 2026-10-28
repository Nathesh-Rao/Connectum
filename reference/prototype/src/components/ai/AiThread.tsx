import { useLayoutEffect, useRef, useState } from "react"
import { AnimatePresence, motion } from "motion/react"
import { useApp } from "../../app-state"
import type { AiChat, AiMessage } from "../../data/ai"
import { distance, duration, useMotionPrefs } from "../../motion"
import { Button } from "../Button"
import { ThinkingDots } from "../conversation/SummaryPanel"
import { Icon } from "../Icon"

function Actions({ message }: { message: AiMessage }) {
  const { ai } = useApp()
  const { press, reduce } = useMotionPrefs()
  const [copied, setCopied] = useState(false)
  const pop = reduce ? undefined : { scale: [1, 1.25, 1] }
  return (
    <motion.div
      className="ai-actions"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: duration.base }}
    >
      <Button
        className="ai-act"
        aria-label="Copy"
        onClick={() => {
          navigator.clipboard?.writeText(message.text)
          setCopied(true)
          setTimeout(() => setCopied(false), 1400)
        }}
      >
        <AnimatePresence mode="wait" initial={false}>
          <motion.span
            key={copied ? "ok" : "copy"}
            initial={{ opacity: 0, scale: reduce ? 1 : 0.6 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: reduce ? 1 : 0.6 }}
            transition={{ duration: duration.fast }}
            style={{ display: "flex" }}
          >
            <Icon name={copied ? "check" : "copy"} />
          </motion.span>
        </AnimatePresence>
      </Button>
      <Button
        className="ai-act"
        aria-label="Regenerate"
        onClick={() => ai.regenerate(message.id)}
      >
        <Icon name="refresh" />
      </Button>
      {(["up", "down"] as const).map((kind) => (
        <Button
          key={kind}
          className={"ai-act" + (message.feedback === kind ? " on" : "")}
          aria-label={kind === "up" ? "Good response" : "Bad response"}
          aria-pressed={message.feedback === kind}
          onClick={() => ai.setFeedback(message.id, kind)}
        >
          <motion.span
            key={String(message.feedback === kind)}
            animate={message.feedback === kind ? pop : undefined}
            transition={press}
            style={{ display: "flex" }}
          >
            <Icon name={kind === "up" ? "thumbUp" : "thumbDown"} />
          </motion.span>
        </Button>
      ))}
    </motion.div>
  )
}

function Message({ message }: { message: AiMessage }) {
  const { reduce, spring } = useMotionPrefs()
  if (message.role === "user")
    return (
      <motion.div
        className="ai-user"
        initial={{
          opacity: 0,
          y: reduce ? 0 : distance.rise,
          scale: reduce ? 1 : 0.97,
        }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={spring}
      >
        {message.text}
      </motion.div>
    )
  return (
    <motion.div
      className="ai-assistant"
      initial={{ opacity: 0, y: reduce ? 0 : distance.rise }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: duration.base }}
    >
      <span className="ai-av">
        <Icon name="spark" />
      </span>
      <div className="ai-content">
        {message.status === "thinking" ? (
          <ThinkingDots />
        ) : (
          <p>{message.text}</p>
        )}
        {message.status === "done" && <Actions message={message} />}
      </div>
    </motion.div>
  )
}

// Messages with auto-scroll while streaming. Scrolling up pauses it and
// shows a pill to jump back to the latest.
export function AiThread({ chat }: { chat: AiChat }) {
  const { reduce, tween } = useMotionPrefs()
  const ref = useRef<HTMLDivElement>(null)
  const stick = useRef(true)
  const [pill, setPill] = useState(false)
  const signature = chat.messages.map((m) => m.text.length + m.status).join("|")
  const count = chat.messages.length

  const toBottom = (smooth: boolean) => {
    const el = ref.current
    if (el)
      el.scrollTo({
        top: el.scrollHeight,
        behavior: smooth && !reduce ? "smooth" : "auto",
      })
  }
  useLayoutEffect(() => {
    stick.current = true
    toBottom(false)
  }, [chat.id]) // eslint-disable-line react-hooks/exhaustive-deps
  useLayoutEffect(() => {
    stick.current = true
    toBottom(true)
  }, [count]) // eslint-disable-line react-hooks/exhaustive-deps
  useLayoutEffect(() => {
    if (stick.current) toBottom(false)
    else setPill(true)
  }, [signature]) // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <motion.div
      className="ai-thread-wrap"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={tween(duration.base)}
    >
      <div
        className="ai-thread"
        ref={ref}
        onScroll={(e) => {
          const el = e.currentTarget
          const near = el.scrollHeight - el.scrollTop - el.clientHeight < 80
          stick.current = near
          if (near) setPill(false)
        }}
      >
        {chat.messages.map((m) => (
          <Message key={m.id} message={m} />
        ))}
      </div>
      <AnimatePresence>
        {pill && (
          <motion.button
            className="latest-pill"
            initial={{ opacity: 0, y: reduce ? 0 : 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: reduce ? 0 : 8 }}
            transition={tween(duration.fast)}
            onClick={() => {
              stick.current = true
              toBottom(true)
              setPill(false)
            }}
          >
            <Icon name="down" />
            Latest
          </motion.button>
        )}
      </AnimatePresence>
    </motion.div>
  )
}
