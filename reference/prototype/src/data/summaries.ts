import type {
  Submission,
  Thread,
  TextMessage,
  FormMessage,
} from "./conversations"
import { statusOf, summaryLine } from "./submissions"

export const summaryChips = [
  "Summarise today",
  "Last 7 days",
  "Action items",
  "Submissions only",
]

const clip = (s: string, n = 70) => (s.length > n ? s.slice(0, n - 1) + "…" : s)

// Builds a canned summary from this conversation's own messages and
// submission cards. Nothing leaves the device.
export function buildSummary(
  kind: string,
  name: string,
  thread: Thread,
  submissions: Submission[],
) {
  const texts = thread.messages.filter(
    (m): m is TextMessage => m.kind === "text",
  )
  const mine = texts.filter((m) => m.from === "me").length
  const cards = thread.messages
    .filter((m): m is FormMessage => m.kind === "form")
    .map((m) => submissions.find((s) => s.id === m.submissionId))
    .filter((s): s is Submission => !!s)
  const subLines = cards.map(
    (s) =>
      `• #${s.id} ${s.title}${
        summaryLine(s) ? " · " + summaryLine(s) : ""
      } · ${statusOf(s)}`,
  )
  const last = texts[texts.length - 1]

  if (kind === "Submissions only") {
    return cards.length
      ? `Submissions in ${name}:\n\n${subLines.join("\n")}`
      : `There are no submissions in ${name} yet. Use the forms button in the composer to file one.`
  }
  if (kind === "Action items") {
    const asks = texts
      .filter(
        (m) =>
          m.from === "them" &&
          /review|look|ready|needs|due|reminder|ping|fix/i.test(m.text),
      )
      .map((m) => `• Reply to: “${clip(m.text)}”`)
    const pending = cards
      .filter((s) => statusOf(s) === "Pending")
      .map(
        (s) => `• Follow up on submission #${s.id} (${s.title}), still pending`,
      )
    const all = [...asks, ...pending]
    return all.length
      ? `Open action items in ${name}:\n\n${all.join("\n")}`
      : `Nothing is waiting on you in ${name} right now.`
  }
  if (kind === "Summarise today" || kind === "Last 7 days") {
    const head =
      kind === "Last 7 days"
        ? `Over the last 7 days in ${name}:`
        : `Today in ${name}:`
    return [
      head,
      "",
      `• ${texts.length} messages, ${mine} from you.`,
      last ? `• Latest: “${clip(last.text)}”` : "• No messages yet.",
      cards.length
        ? `• ${cards.length} submission${
            cards.length > 1 ? "s" : ""
          } shared:\n${subLines.join("\n")}`
        : "• No submissions shared yet.",
    ].join("\n")
  }
  return `Nothing to summarise in ${name} yet.`
}

export interface Answer {
  text: string
  /** True when a question matched nothing in this chat. */
  empty: boolean
  /** Suggested chips, drawn from what the chat actually contains. */
  followUps: string[]
}

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`

// Answers one question, using only this conversation's messages and cards.
export function answerFor(
  prompt: string,
  name: string,
  thread: Thread,
  submissions: Submission[],
): Answer {
  if (summaryChips.includes(prompt))
    return {
      text: buildSummary(prompt, name, thread, submissions),
      empty: false,
      followUps: [],
    }

  const texts = thread.messages.filter(
    (m): m is TextMessage => m.kind === "text",
  )
  const cards = thread.messages
    .filter((m): m is FormMessage => m.kind === "form")
    .map((m) => submissions.find((s) => s.id === m.submissionId))
    .filter((s): s is Submission => !!s)
  const words = prompt
    .toLowerCase()
    .split(/\W+/)
    .filter((w) => w.length > 3)
  const hits = texts.filter((m) =>
    words.some((w) => m.text.toLowerCase().includes(w)),
  )
  if (hits.length)
    return {
      text: `Here’s what I found about “${clip(prompt, 40)}” in ${name}:\n\n${hits.map((m) => `• “${clip(m.text)}”`).join("\n")}`,
      empty: false,
      followUps: [],
    }

  const hasOpenItems =
    cards.some((c) => statusOf(c) === "Pending") ||
    texts.some(
      (m) =>
        m.from === "them" &&
        /review|look|ready|needs|due|reminder|ping|fix/i.test(m.text),
    )
  const second = hasOpenItems
    ? "Action items"
    : cards.length
      ? "Submissions only"
      : "Last 7 days"
  return {
    text: `Nothing in this chat matches “${clip(prompt, 40)}”. This chat has ${plural(texts.length, "message")} and ${plural(cards.length, "submission")}. I can summarise it or pull out what’s open instead.`,
    empty: true,
    followUps: ["Summarise today", second],
  }
}
