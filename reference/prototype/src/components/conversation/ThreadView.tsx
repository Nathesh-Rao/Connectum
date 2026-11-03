import { useLayoutEffect, useRef } from "react"
import { motion } from "motion/react"
import type { Submission, Thread } from "../../data/conversations"
import { distance, duration, useMotionPrefs } from "../../motion"
import { FormCard } from "../FormCard"
import { useSettled } from "../Landing"

interface ThreadViewProps {
  thread: Thread
  submissions: Submission[]
  pulses: Record<number, number>
  onOpen: (id: number) => void
  onEdit: (id: number) => void
}

// The message list. Opens at the latest message and glides to new ones.
export function ThreadView({
  thread,
  submissions,
  pulses,
  onOpen,
  onEdit,
}: ThreadViewProps) {
  const { reduce, tween } = useMotionPrefs()
  const settled = useSettled()
  const ref = useRef<HTMLDivElement>(null)
  const count = thread.messages.length
  const first = useRef(true)
  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    el.scrollTo({
      top: el.scrollHeight,
      behavior: first.current || reduce ? "auto" : "smooth",
    })
    first.current = false
  }, [count, reduce])

  return (
    <div className="thread" ref={ref}>
      <div className="day">{thread.day}</div>
      <div className="notice">{thread.notice}</div>
      {thread.messages.map((m) => {
        if (m.kind === "divider")
          return (
            <div className="unread-divider" key={m.id}>
              {m.label}
            </div>
          )
        if (m.kind === "form") {
          const submission = submissions.find((s) => s.id === m.submissionId)
          if (!submission) return null
          return (
            <div key={m.id} className={"card-row " + submission.direction}>
              <div className="card-col">
                <FormCard
                  submission={submission}
                  fly={m.fly}
                  pulse={pulses[submission.id]}
                  onOpen={() => onOpen(submission.id)}
                  onEdit={
                    submission.direction === "sent"
                      ? () => onEdit(submission.id)
                      : undefined
                  }
                />
              </div>
            </div>
          )
        }
        const mine = m.from === "me"
        return (
          <div key={m.id} className="msg">
            <motion.div
              className={"bubble " + (mine ? "outgoing" : "incoming")}
              initial={
                settled.current
                  ? { opacity: 0, y: reduce ? 0 : distance.rise }
                  : false
              }
              animate={{ opacity: 1, y: 0 }}
              transition={tween(duration.base)}
            >
              {m.text}
            </motion.div>
            {m.time && (
              <small className={"timestamp" + (mine ? " right" : "")}>
                {m.time}
                {m.note ? ` · ${m.note}` : ""}
              </small>
            )}
          </div>
        )
      })}
      {thread.typing && (
        <div className="typing">
          ••• <span>{thread.typing} is typing</span>
        </div>
      )}
    </div>
  )
}
