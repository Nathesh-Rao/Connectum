import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type RefObject,
} from "react"
import {
  animate,
  AnimatePresence,
  motion,
  useMotionValue,
  useMotionValueEvent,
  type MotionValue,
} from "motion/react"
import type { Submission, Thread } from "../../data/conversations"
import { conversationInfo } from "../../data/conversations"
import { answerFor, summaryChips } from "../../data/summaries"
import { distance, duration, ease, useMotionPrefs } from "../../motion"
import { useStream } from "../../state/use-stream"
import type { Pin } from "../../state/chat-store"
import { Avatar } from "../Avatar"
import { Button } from "../Button"
import { Icon } from "../Icon"
import { useLoop } from "../onboarding/motionKit"

interface SummaryPanelProps {
  name: string
  thread: Thread
  submissions: Submission[]
  container: RefObject<HTMLDivElement | null>
  /** 0 = closed, 1 = at the 60% resting height. Drives the chat behind. */
  progress: MotionValue<number>
  onPin: (pin: Pin) => void
  onClose: () => void
  /** Hands a question that found nothing here over to the AI tab. */
  onAskAll: (question: string) => void
}

interface Turn {
  id: number
  prompt: string
  full: string
  empty: boolean
  followUps: string[]
}

// A mini AI window scoped to one conversation, in three zones: a header, a
// scrollable thread of questions and answers, and a dock pinned to the
// bottom with the quick chips and the input. It rests at 60% of the chat and
// resizes from the bottom edge, so the dock is always inside the visible
// area. Only the grip and header start a drag; the thread and input never do.
export function SummaryPanel({
  name,
  thread,
  submissions,
  container,
  progress,
  onPin,
  onClose,
  onAskAll,
}: SummaryPanelProps) {
  const { reduce, spring, press, tween } = useMotionPrefs()
  const H = container.current?.clientHeight ?? 700
  const HALF = Math.round(H * 0.6)
  const FULL = Math.round(H * 0.94)
  const height = useMotionValue(0)
  const stream = useStream()
  const [turns, setTurns] = useState<Turn[]>([])
  const [question, setQuestion] = useState("")
  const [copied, setCopied] = useState<number | null>(null)
  const body = useRef<HTMLDivElement>(null)
  const stick = useRef(true)
  const grab = useRef(0)
  const info = conversationInfo(name)
  const busy = stream.status === "thinking" || stream.status === "streaming"
  const ready = !!question.trim() && !busy

  useMotionValueEvent(height, "change", (v) =>
    progress.set(Math.min(1, Math.max(0, v / HALF))),
  )
  useEffect(() => () => progress.set(0), [progress])

  // Follow the answer as it streams, unless the user scrolled up to read.
  useLayoutEffect(() => {
    const el = body.current
    if (el && stick.current) el.scrollTop = el.scrollHeight
  }, [turns.length, stream.text, stream.status])

  const ask = (prompt: string) => {
    const clean = prompt.trim()
    if (!clean || busy) return
    const {
      text: full,
      empty,
      followUps,
    } = answerFor(clean, name, thread, submissions)
    setTurns((t) => [
      ...t,
      { id: t.length + 1, prompt: clean, full, empty, followUps },
    ])
    stick.current = true
    stream.start(full)
  }

  return (
    <motion.section
      className="sum-panel"
      style={{ height }}
      initial={{ height: 0 }}
      animate={{ height: HALF }}
      exit={{ height: 0, transition: tween(duration.base) }}
      transition={spring}
    >
      <motion.div
        className="sum-grip"
        onPanStart={() => (grab.current = height.get())}
        onPan={(_, { offset }) =>
          height.set(Math.min(FULL + 24, Math.max(0, grab.current - offset.y)))
        }
        onPanEnd={(_, { velocity }) => {
          const at = height.get() - velocity.y * 0.15
          const snap = [0, HALF, FULL].reduce((a, b) =>
            Math.abs(b - at) < Math.abs(a - at) ? b : a,
          )
          if (snap === 0) onClose()
          else
            animate(height, snap, reduce ? { duration: duration.reduced } : spring)
        }}
      >
        <div className="handle" />
        <div className="sum-title">
          <span className="sum-spark">
            <Icon name="spark" />
          </span>
          <h2>Summarise this chat</h2>
          <Button className="icon-button" aria-label="Close" onClick={onClose}>
            <Icon name="close" />
          </Button>
        </div>
        <motion.div
          className="scope-chip"
          initial={{ opacity: 0, y: reduce ? 0 : distance.rise }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.12, duration: duration.base, ease: ease.out }}
        >
          <Avatar name={info.initial} tone={info.tone} />
          Reading: <strong>{name}</strong>
        </motion.div>
      </motion.div>

      <div
        className="sum-body"
        ref={body}
        onScroll={(e) => {
          const el = e.currentTarget
          stick.current = el.scrollHeight - el.scrollTop - el.clientHeight < 60
        }}
      >
        {!turns.length && (
          <p className="sum-hint">
            Pick a quick summary or ask something about this conversation.
          </p>
        )}
        {turns.map((turn, i) => {
          const last = i === turns.length - 1
          const text = last ? stream.text : turn.full
          const thinking = last && stream.status === "thinking"
          const done = !last || stream.status === "done"
          return (
            <div className="sum-turn" key={turn.id}>
              <motion.div
                className="sum-user"
                initial={{ opacity: 0, y: reduce ? 0 : distance.rise }}
                animate={{ opacity: 1, y: 0 }}
                transition={spring}
              >
                {turn.prompt}
              </motion.div>
              <motion.div
                className="sum-card"
                initial={{ opacity: 0, y: reduce ? 0 : distance.rise }}
                animate={{ opacity: 1, y: 0 }}
                transition={tween(duration.base)}
              >
                {thinking ? <ThinkingDots /> : <p>{text}</p>}
                <AnimatePresence initial={false}>
                  {done && turn.empty && (
                    <motion.div
                      key="follow"
                      className="sum-follow"
                      initial={{ opacity: 0, y: reduce ? 0 : distance.rise }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={tween(duration.base)}
                    >
                      {turn.followUps.map((chip) => (
                        <Button
                          key={chip}
                          className="chip"
                          disabled={busy}
                          onClick={() => ask(chip)}
                        >
                          {chip}
                        </Button>
                      ))}
                    </motion.div>
                  )}
                  {done && (
                    <motion.div
                      key="actions"
                      className="sum-actions"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      transition={tween(duration.base)}
                    >
                      <Button
                        className="chip"
                        onClick={() => {
                          navigator.clipboard?.writeText(turn.full)
                          setCopied(turn.id)
                          setTimeout(() => setCopied(null), 1400)
                        }}
                      >
                        <Icon name={copied === turn.id ? "check" : "copy"} />
                        {copied === turn.id ? "Copied" : "Copy"}
                      </Button>
                      <Button
                        className="chip chip-primary"
                        onClick={() => {
                          onPin({ title: turn.prompt, text: turn.full })
                          onClose()
                        }}
                      >
                        <Icon name="pin" />
                        Pin to chat
                      </Button>
                    </motion.div>
                  )}
                  {done && turn.empty && (
                    <motion.div
                      key="link"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      transition={tween(duration.base)}
                    >
                      <Button
                        className="link-btn"
                        onClick={() => onAskAll(turn.prompt)}
                      >
                        Ask across all chats instead
                        <Icon name="arrow" />
                      </Button>
                    </motion.div>
                  )}
                </AnimatePresence>
              </motion.div>
            </div>
          )
        })}
      </div>

      <div className="sum-dock">
        <div className="sum-chips">
          {summaryChips.map((chip) => (
            <Button
              key={chip}
              className="chip"
              disabled={busy}
              onClick={() => ask(chip)}
            >
              {chip}
            </Button>
          ))}
        </div>
        <AnimatePresence initial={false}>
          {!turns.length && (
            <motion.p
              className="sum-scope-hint"
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: "auto" }}
              exit={{ opacity: 0, height: 0 }}
              transition={tween(duration.base)}
            >
              I only look at messages and submissions in this chat.
            </motion.p>
          )}
        </AnimatePresence>
        <form
          className="sum-input"
          onSubmit={(e) => {
            e.preventDefault()
            if (!ready) return
            ask(question)
            setQuestion("")
          }}
        >
          <input
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            placeholder="Ask about this chat..."
            enterKeyHint="send"
          />
          <motion.button
            className="ai-send"
            type="submit"
            aria-label="Send"
            disabled={!ready}
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
        </form>
      </div>
    </motion.section>
  )
}

export function ThinkingDots() {
  const loop = useLoop()
  return (
    <span className="thinking" aria-label="Thinking">
      {[0, 1, 2].map((i) => (
        <motion.i
          key={i}
          {...loop({ opacity: [0.4, 1, 0.4], y: [0, -3, 0] }, {
            duration: 0.9,
            repeat: Infinity,
            delay: i * 0.15,
            ease: ease.inOut,
          })}
        />
      ))}
    </span>
  )
}
