export interface AiMessage {
  id: string
  role: "user" | "assistant"
  text: string
  status: "thinking" | "streaming" | "done"
  feedback?: "up" | "down"
}

export interface AiChat {
  id: string
  title: string
  updated: string
  messages: AiMessage[]
}

export const aiSuggestions = [
  "What needs my attention?",
  "Build a report from my Data Bin",
  "Summarise my chats",
]

interface Reply {
  match: RegExp
  texts: string[]
}

const replies: Reply[] = [
  {
    match: /attention|urgent|priority/i,
    texts: [
      "Here’s what needs your attention today:\n\n1. Priya Sharma shared an updated workflow and is waiting on your review (2 unread).\n2. Submission #1042 (chart_test, ₹1,200) is marked Paid. Worth a quick confirmation with finance.\n3. Arjun Mehta’s proposal needs feedback, mainly on the pricing section.\n\nWant me to draft replies for any of these?",
      "Three things are open right now:\n\n1. Review Priya’s updated workflow.\n2. Confirm submission #1042 with finance.\n3. Comment on Arjun’s proposal before the end of the day.\n\nI can turn these into a checklist if that helps.",
    ],
  },
  {
    match: /report|data bin/i,
    texts: [
      "I pulled a draft from your Data Bin. Last 30 days:\n\n• 12 submissions, ₹14,400 in total\n• Top department: Ortho (5 submissions)\n• 3 submissions are still pending\n• Average turnaround: 1.4 days\n\nSay “export” and I’ll prepare a shareable summary.",
      "Here’s a report outline based on your Data Bin:\n\n• Period: last 30 days\n• Volume: 12 submissions across 4 departments\n• Revenue: ₹14,400, up 8% on the previous month\n• Follow-ups: 3 pending, 1 overdue\n\nWant a version split by department?",
    ],
  },
  {
    match: /summar/i,
    texts: [
      "A quick summary of your chats:\n\n• Priya Sharma: workflow approved, submission #1042 sent.\n• Design Collective: new icon set and components shared.\n• Arjun Mehta: proposal waiting for your review.\n• Product & Engineering: Friday release on track.",
      "Across your conversations today: the workflow is approved, one submission went out, the design library was updated, and the Friday release is on track. Arjun’s proposal is the only thing waiting on you.",
    ],
  },
]

const fallback = [
  "Happy to help with that. Based on what’s in your workspace, I’d start by breaking it into two steps: gather the details from your recent chats, then draft the result for you to review. Want me to begin?",
  "Good question. Here’s a short take: keep it simple, confirm the key details with the people involved, and I can prepare a first draft you can edit. Shall I go ahead?",
]

export function aiReply(prompt: string, attempt = 0) {
  const hit = replies.find((r) => r.match.test(prompt))
  const pool = hit ? hit.texts : fallback
  return pool[attempt % pool.length]
}

export const seedAiChats: AiChat[] = [
  {
    id: "seed-1",
    title: "Weekly attention list",
    updated: "Yesterday",
    messages: [
      {
        id: "s1a",
        role: "user",
        text: "What needs my attention?",
        status: "done",
      },
      {
        id: "s1b",
        role: "assistant",
        text: replies[0].texts[1],
        status: "done",
      },
    ],
  },
  {
    id: "seed-2",
    title: "Data Bin report draft",
    updated: "Mon",
    messages: [
      {
        id: "s2a",
        role: "user",
        text: "Build a report from my Data Bin",
        status: "done",
      },
      {
        id: "s2b",
        role: "assistant",
        text: replies[1].texts[0],
        status: "done",
      },
    ],
  },
  {
    id: "seed-3",
    title: "Chat summary: Design Collective",
    updated: "Last week",
    messages: [
      { id: "s3a", role: "user", text: "Summarise my chats", status: "done" },
      {
        id: "s3b",
        role: "assistant",
        text: replies[2].texts[0],
        status: "done",
      },
    ],
  },
]
