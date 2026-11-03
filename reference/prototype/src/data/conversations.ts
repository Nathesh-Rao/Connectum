export type Tone = "peach" | "lavender" | "sage" | "sand"

export interface ConversationInfo {
  name: string
  initial: string
  tone: Tone
  preview: string
  time: string
  count: number
  type: "Direct message" | "Group" | "Team"
  photo?: boolean
}

export const conversations: ConversationInfo[] = [
  {
    name: "Priya Sharma",
    initial: "PS",
    tone: "peach",
    preview: "The new flow looks great. Let’s ship it!",
    time: "2m",
    count: 2,
    type: "Direct message",
    photo: true,
  },
  {
    name: "Design Collective",
    initial: "DC",
    tone: "lavender",
    preview: "You: Shared the updated components",
    time: "12m",
    count: 3,
    type: "Group",
  },
  {
    name: "Arjun Mehta",
    initial: "AM",
    tone: "sage",
    preview: "Can you take a look at the proposal?",
    time: "28m",
    count: 0,
    type: "Direct message",
  },
  {
    name: "Product & Engineering",
    initial: "PE",
    tone: "sand",
    preview: "Nina: Friday release is looking good",
    time: "1h",
    count: 0,
    type: "Team",
  },
]

const senderTones: Tone[] = ["peach", "lavender", "sage", "sand"]

/** A stable avatar tone for someone who isn't a conversation. */
export function toneFor(name: string): Tone {
  const known = conversations.find((c) => c.name === name)
  if (known) return known.tone
  let h = 0
  for (const ch of name) h = (h * 31 + ch.charCodeAt(0)) % 997
  return senderTones[h % senderTones.length]
}

export function initialsOf(name: string) {
  return name
    .split(/\s+/)
    .map((w) => w[0])
    .join("")
    .slice(0, 2)
    .toUpperCase()
}

export function conversationInfo(name: string) {
  const known = conversations.find((c) => c.name === name)
  if (known) return known
  if (name === "My Work Space")
    return { initial: "#", tone: "sage" as Tone, name, photo: false }
  const initial = name
    .split(/\s+/)
    .map((w) => w[0])
    .join("")
    .slice(0, 2)
    .toUpperCase()
  return { initial, tone: "peach" as Tone, name, photo: false }
}

// ---- Messages --------------------------------------------------------------
export interface TextMessage {
  id: string
  kind: "text"
  from: "me" | "them"
  text: string
  time?: string
  note?: string
}
export interface FormMessage {
  id: string
  kind: "form"
  submissionId: number
  fly?: boolean
}
export interface DividerMessage {
  id: string
  kind: "divider"
  label: string
}
export type Message = TextMessage | FormMessage | DividerMessage

export interface Thread {
  day: string
  notice: string
  typing?: string
  messages: Message[]
}

export interface Submission {
  id: number
  form: string
  title: string
  time: string
  /** "sent" cards are mine (editable); "received" cards are read-only. */
  direction: "sent" | "received"
  sender: string
  /** What was entered, keyed by the form's field names. */
  values: Record<string, string>
}

export const seedSubmissions: Submission[] = [
  {
    id: 1042,
    form: "Clinical examination - Ortho",
    title: "Clinical examination - Ortho",
    time: "Today at 10:28 AM",
    direction: "received",
    sender: "Priya Sharma",
    values: {
      area: "Right knee",
      general: "Mild swelling, normal gait",
      tests: "X-ray, range of motion",
      department: "Ortho",
      date: "2026-10-21",
      followUp: "Yes",
      amount: "1200",
      status: "Paid",
    },
  },
  {
    id: 1041,
    form: "Prescribe medicine",
    title: "Prescribe medicine",
    time: "Today at 9:52 AM",
    direction: "received",
    sender: "Arjun Mehta",
    values: {
      medicine: "Amoxicillin 500 mg",
      dosage: "1 tablet twice daily",
      duration: "5 days",
      refill: "No",
      amount: "480",
      status: "Paid",
    },
  },
  {
    id: 1040,
    form: "Advice & review",
    title: "Advice & review",
    time: "Today at 10:27 AM",
    direction: "sent",
    sender: "Alex Morgan",
    values: {
      diet: "test",
      general: "test",
      message: "test",
      physio: "Yes",
      surgery: "No",
      dietician: "No",
      ip: "Yes",
      patient: "Sabarish",
      review: "Review not required",
    },
  },
  {
    id: 1039,
    form: "Prescribe lab test",
    title: "Prescribe lab test",
    time: "Today at 10:05 AM",
    direction: "received",
    sender: "Mira Kapoor",
    values: {
      test: "Complete blood count",
      instructions: "Collect before 10 AM",
      fasting: "Yes",
      amount: "640",
      status: "Paid",
    },
  },
  {
    id: 1038,
    form: "Referral",
    title: "Referral",
    time: "Today at 9:18 AM",
    direction: "received",
    sender: "Nina Alvarez",
    values: {
      to: "Dr. Rao, Orthopaedics",
      reason: "Persistent knee pain after physiotherapy",
      urgent: "No",
      status: "Pending",
    },
  },
]

const day = "Today, October 21"
const notice = "This is your space to move work forward."

export const seedThreads: Record<string, Thread> = {
  "Priya Sharma": {
    day,
    notice,
    typing: "Priya",
    messages: [
      {
        id: "p1",
        kind: "text",
        from: "them",
        text: "Hey Alex! The updated workflow is ready for your review.",
        time: "10:24 AM",
      },
      {
        id: "p2",
        kind: "text",
        from: "me",
        text: "Looks great, Priya. The simpler the better. Let’s get this moving.",
        time: "10:26 AM",
        note: "Read",
      },
      { id: "p2b", kind: "form", submissionId: 1040 },
      { id: "p3", kind: "divider", label: "2 new messages" },
      {
        id: "p4",
        kind: "text",
        from: "them",
        text: "Just submitted the visit details. Everything’s in here ↓",
      },
      { id: "p5", kind: "form", submissionId: 1042 },
    ],
  },
  "Design Collective": {
    day,
    notice: "Group · 6 members",
    messages: [
      {
        id: "d1",
        kind: "text",
        from: "them",
        text: "Mira: Uploaded the new icon set to the library.",
        time: "9:58 AM",
      },
      {
        id: "d2",
        kind: "text",
        from: "me",
        text: "Shared the updated components. Spacing tokens are in too.",
        time: "10:12 AM",
        note: "Delivered",
      },
      {
        id: "d3",
        kind: "text",
        from: "them",
        text: "Dev: These look crisp. Reviewing the empty states next.",
        time: "10:20 AM",
      },
      {
        id: "d4",
        kind: "text",
        from: "them",
        text: "Mira: Filed the lab request for the usability study ↓",
      },
      { id: "d5", kind: "form", submissionId: 1039 },
    ],
  },
  "Arjun Mehta": {
    day,
    notice,
    messages: [
      {
        id: "a1",
        kind: "text",
        from: "them",
        text: "Can you take a look at the proposal?",
        time: "9:41 AM",
      },
      {
        id: "a2",
        kind: "text",
        from: "me",
        text: "Sure, I’ll go through it after standup and leave comments.",
        time: "9:44 AM",
        note: "Read",
      },
      {
        id: "a3",
        kind: "text",
        from: "them",
        text: "Perfect. The pricing section needs the most attention.",
        time: "9:46 AM",
      },
      {
        id: "a4",
        kind: "text",
        from: "them",
        text: "Also sent the prescription details. The cost is in the card ↓",
      },
      { id: "a5", kind: "form", submissionId: 1041 },
    ],
  },
  "Product & Engineering": {
    day,
    notice: "Team · 14 members",
    messages: [
      {
        id: "e1",
        kind: "text",
        from: "them",
        text: "Nina: Friday release is looking good. QA is almost done.",
        time: "9:05 AM",
      },
      {
        id: "e2",
        kind: "text",
        from: "them",
        text: "Sam: Two small fixes left on the checkout flow.",
        time: "9:12 AM",
      },
      {
        id: "e3",
        kind: "text",
        from: "me",
        text: "Great. Ping me when the release notes are ready to review.",
        time: "9:20 AM",
        note: "Read",
      },
      {
        id: "e4",
        kind: "text",
        from: "them",
        text: "Nina: Sent the referral for the support escalation ↓",
      },
      { id: "e5", kind: "form", submissionId: 1038 },
    ],
  },
  "My Work Space": {
    day,
    notice,
    messages: [
      {
        id: "w1",
        kind: "text",
        from: "them",
        text: "Reminder: your weekly timesheet is due by 6 PM.",
        time: "8:30 AM",
      },
      {
        id: "w2",
        kind: "text",
        from: "them",
        text: "Tip: tap the forms button to file an update without leaving the chat.",
        time: "8:31 AM",
      },
    ],
  },
}

export function emptyThread(): Thread {
  return { day, notice, messages: [] }
}

export function nowTime() {
  return new Date().toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit",
  })
}
