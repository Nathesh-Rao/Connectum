import { useCallback, useEffect, useRef, useState } from "react"
import { aiReply, seedAiChats, type AiChat, type AiMessage } from "../data/ai"

const THINK_MS = 900
const WORD_MS = 42

// Simulated assistant: canned replies, a "thinking" beat, then word by word.
// Lives at the app level so a reply keeps streaming if you switch tabs.
export function useAiStore() {
  const [chats, setChats] = useState<AiChat[]>(seedAiChats)
  const [activeId, setActiveId] = useState<string | null>(null)
  const [draft, setDraft] = useState("")
  const [model, setModel] = useState<"Auto" | "Fast" | "Thinking">("Auto")
  const counter = useRef(0)
  const timers = useRef<number[]>([])
  const attempts = useRef<Record<string, number>>({})
  useEffect(() => () => timers.current.forEach((t) => clearTimeout(t)), [])

  const patch = useCallback(
    (chatId: string, messageId: string, fn: (m: AiMessage) => AiMessage) =>
      setChats((prev) =>
        prev.map((c) =>
          c.id === chatId
            ? {
                ...c,
                messages: c.messages.map((m) =>
                  m.id === messageId ? fn(m) : m,
                ),
              }
            : c,
        ),
      ),
    [],
  )

  const stream = useCallback(
    (chatId: string, messageId: string, prompt: string) => {
      const attempt = (attempts.current[messageId] =
        (attempts.current[messageId] ?? -1) + 1)
      const tokens = aiReply(prompt, attempt).split(/(\s+)/)
      let i = 0
      timers.current.push(
        window.setTimeout(() => {
          patch(chatId, messageId, (m) => ({ ...m, status: "streaming" }))
          const id = window.setInterval(() => {
            i += 2 // a word and the whitespace after it
            const done = i >= tokens.length
            patch(chatId, messageId, (m) => ({
              ...m,
              text: tokens.slice(0, i).join(""),
              status: done ? "done" : "streaming",
            }))
            if (done) clearInterval(id)
          }, WORD_MS)
          timers.current.push(id)
        }, THINK_MS),
      )
    },
    [patch],
  )

  const send = useCallback(
    (text: string) => {
      const clean = text.trim()
      if (!clean) return
      const chatId = activeId ?? `ai${++counter.current}`
      const user: AiMessage = {
        id: `u${++counter.current}`,
        role: "user",
        text: clean,
        status: "done",
      }
      const reply: AiMessage = {
        id: `a${++counter.current}`,
        role: "assistant",
        text: "",
        status: "thinking",
      }
      setChats((prev) =>
        prev.some((c) => c.id === chatId)
          ? prev.map((c) =>
              c.id === chatId
                ? { ...c, messages: [...c.messages, user, reply] }
                : c,
            )
          : [
              {
                id: chatId,
                title: clean.length > 38 ? clean.slice(0, 36) + "…" : clean,
                updated: "Just now",
                messages: [user, reply],
              },
              ...prev,
            ],
      )
      setActiveId(chatId)
      stream(chatId, reply.id, clean)
    },
    [activeId, stream],
  )

  const regenerate = useCallback(
    (messageId: string) => {
      const chat = chats.find((c) => c.id === activeId)
      if (!chat) return
      const index = chat.messages.findIndex((m) => m.id === messageId)
      const prompt = chat.messages[index - 1]?.text
      if (!prompt) return
      patch(chat.id, messageId, (m) => ({
        ...m,
        text: "",
        status: "thinking",
        feedback: undefined,
      }))
      stream(chat.id, messageId, prompt)
    },
    [activeId, chats, patch, stream],
  )

  const setFeedback = useCallback(
    (messageId: string, feedback: "up" | "down") => {
      if (!activeId) return
      patch(activeId, messageId, (m) => ({
        ...m,
        feedback: m.feedback === feedback ? undefined : feedback,
      }))
    },
    [activeId, patch],
  )

  return {
    draft,
    setDraft,
    model,
    setModel,
    chats,
    activeId,
    active: chats.find((c) => c.id === activeId) ?? null,
    send,
    regenerate,
    setFeedback,
    newChat: () => setActiveId(null),
    openChat: (id: string) => setActiveId(id),
  }
}

export type AiStore = ReturnType<typeof useAiStore>
