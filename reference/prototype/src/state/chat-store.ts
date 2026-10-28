import { useCallback, useEffect, useRef, useState } from "react"
import {
  nowTime,
  emptyThread,
  seedSubmissions,
  seedThreads,
  type Message,
  type Submission,
  type Thread,
} from "../data/conversations"
import { initialRecentForms } from "../data/forms"

export interface Pin {
  title: string
  text: string
}

// Conversations, submissions, forms and pinned summaries. Messages are kept
// per conversation, so sent messages and form cards land in the right chat.
export function useChatStore() {
  const [threads, setThreads] = useState<Record<string, Thread>>(seedThreads)
  const [submissions, setSubmissions] = useState<Submission[]>(seedSubmissions)
  const [selected, setSelected] = useState(seedSubmissions[0].id)
  const [recentForms, setRecentForms] = useState(initialRecentForms)
  const [pulses, setPulses] = useState<Record<number, number>>({})
  const [pins, setPins] = useState<Record<string, Pin>>({})
  const counter = useRef(0)
  const timers = useRef<number[]>([])
  useEffect(() => () => timers.current.forEach(clearTimeout), [])

  const append = useCallback((conv: string, message: Message) => {
    setThreads((prev) => {
      const thread = prev[conv] ?? emptyThread()
      return {
        ...prev,
        [conv]: { ...thread, messages: [...thread.messages, message] },
      }
    })
  }, [])

  const sendMessage = useCallback(
    (conv: string, text: string) => {
      const clean = text.trim()
      if (!clean) return
      append(conv, {
        id: `m${++counter.current}`,
        kind: "text",
        from: "me",
        text: clean,
        time: nowTime(),
        note: "Delivered",
      })
    },
    [append],
  )

  const addSubmission = useCallback(
    (conv: string, formName: string, values: Record<string, string>) => {
      const id = Math.max(...submissions.map((x) => x.id)) + 1
      const submission: Submission = {
        id,
        form: formName,
        title: formName,
        time: `Today at ${nowTime()}`,
        direction: "sent",
        sender: "Alex Morgan",
        values,
      }
      setSubmissions((prev) => [submission, ...prev])
      setRecentForms((prev) =>
        [formName, ...prev.filter((n) => n !== formName)].slice(0, 3),
      )
      const messageId = `m${++counter.current}`
      append(conv, { id: messageId, kind: "form", submissionId: id, fly: true })
      // The fly-in only plays once; clear the flag so remounts stay quiet.
      timers.current.push(
        window.setTimeout(() => {
          setThreads((prev) => {
            const thread = prev[conv]
            if (!thread) return prev
            return {
              ...prev,
              [conv]: {
                ...thread,
                messages: thread.messages.map((m) =>
                  m.id === messageId && m.kind === "form"
                    ? { ...m, fly: false }
                    : m,
                ),
              },
            }
          })
        }, 2500),
      )
      setSelected(id)
      return submission
    },
    [append, submissions],
  )

  // Saves an edit into the existing submission (same id) and flags the card
  // so it can pulse once.
  const editSubmission = useCallback(
    (id: number, values: Record<string, string>) => {
      setSubmissions((prev) =>
        prev.map((x) => (x.id === id ? { ...x, values } : x)),
      )
      setPulses((prev) => ({ ...prev, [id]: (prev[id] ?? 0) + 1 }))
    },
    [],
  )

  const pinSummary = useCallback((conv: string, pin: Pin | null) => {
    setPins((prev) => {
      const next = { ...prev }
      if (pin) next[conv] = pin
      else delete next[conv]
      return next
    })
  }, [])

  return {
    threads,
    submissions,
    selected,
    setSelected,
    recentForms,
    pins,
    sendMessage,
    addSubmission,
    editSubmission,
    pulses,
    pinSummary,
  }
}
