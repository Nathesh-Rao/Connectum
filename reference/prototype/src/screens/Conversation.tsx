import { useRef, useState } from "react"
import {
  AnimatePresence,
  motion,
  useMotionValue,
  useTransform,
} from "motion/react"
import { useApp } from "../app-state"
import { Avatar } from "../components/Avatar"
import { Button } from "../components/Button"
import { PinnedSummary } from "../components/conversation/PinnedSummary"
import { SummaryPanel } from "../components/conversation/SummaryPanel"
import { ThreadView } from "../components/conversation/ThreadView"
import { Icon } from "../components/Icon"
import { conversationInfo, emptyThread } from "../data/conversations"

export function Conversation() {
  const {
    text,
    person,
    threads,
    submissions,
    pins,
    pulses,
    openEdit,
    go,
    setSheet,
    setText,
    sendMessage,
    setFormsQuery,
    selectSubmission,
    pinSummary,
    ai,
  } = useApp()
  const thread = threads[person] ?? emptyThread()
  const info = conversationInfo(person)
  const pin = pins[person]
  const [summary, setSummary] = useState(false)
  const container = useRef<HTMLDivElement>(null)
  // The summary panel reports how far open it is; the chat behind follows.
  const progress = useMotionValue(0)
  const scale = useTransform(progress, [0, 1], [1, 0.965])
  const dim = useTransform(progress, [0, 1], [0, 1])

  return (
    <div className="conv" ref={container}>
      <motion.div className="conv-main" style={{ scale }}>
        <div className="thread-header">
          <Button className="icon-button" onClick={() => go("Chats")}>
            <Icon name="back" />
          </Button>
          <Avatar name={info.initial} tone={info.tone} />
          <Button
            className="thread-name"
            onClick={() => setSheet("Conversation details")}
          >
            <strong>{person}</strong>
            <small>
              <i /> {person === "openai" ? "AI Agent" : "Active now"}
            </small>
          </Button>
          <Button
            className="icon-button summarise"
            aria-label="Summarise this chat"
            onClick={() => setSummary(true)}
          >
            <Icon name="spark" />
          </Button>
          <Button
            className="icon-button"
            aria-label="More"
            onClick={() => setSheet("Conversation tools")}
          >
            <Icon name="more" />
          </Button>
        </div>
        <AnimatePresence initial={false}>
          {pin && (
            <PinnedSummary
              key="pin"
              pin={pin}
              onUnpin={() => pinSummary(person, null)}
            />
          )}
        </AnimatePresence>
        <ThreadView
          thread={thread}
          submissions={submissions}
          pulses={pulses}
          onOpen={(id) => {
            selectSubmission(id)
            go("Submission detail")
          }}
          onEdit={openEdit}
        />
        <div className="composer">
          <Button
            className="icon-button"
            aria-label="Attach"
            onClick={() => setSheet("Attachments")}
          >
            <Icon name="plus" />
          </Button>
          <Button
            className="icon-button forms-btn"
            aria-label="Forms"
            onClick={() => {
              setFormsQuery("")
              setSheet("Forms")
            }}
          >
            <Icon name="grid" />
          </Button>
          <input
            value={text}
            onChange={(e) => {
              setText(e.target.value)
              if (e.target.value === "#") setSheet("Commands")
            }}
            onKeyDown={(e) => e.key === "Enter" && sendMessage()}
            placeholder="Type a message or '#' for commands..."
          />
          <Button
            className="icon-button"
            onClick={
              text ? sendMessage : () => setSheet("Microphone permission")
            }
          >
            <Icon name={text ? "send" : "mic"} />
          </Button>
        </div>
      </motion.div>
      <motion.div
        className="conv-dim"
        style={{ opacity: dim, pointerEvents: summary ? "auto" : "none" }}
        onClick={() => setSummary(false)}
      />
      <AnimatePresence>
        {summary && (
          <SummaryPanel
            key="summary"
            name={person}
            thread={thread}
            submissions={submissions}
            container={container}
            progress={progress}
            onPin={(p) => pinSummary(person, p)}
            onClose={() => setSummary(false)}
            onAskAll={(question) => {
              // Let the panel slide away, then switch tabs with the question
              // waiting, unsent, in a fresh AI chat.
              setSummary(false)
              ai.newChat()
              ai.setDraft(question)
              window.setTimeout(() => go("AI Agents"), 260)
            }}
          />
        )}
      </AnimatePresence>
    </div>
  )
}
