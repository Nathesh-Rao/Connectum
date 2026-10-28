import type { Submission } from "./conversations"
import { forms, type FormField } from "./forms"

const clip = (s: string, n: number) =>
  s.length > n ? s.slice(0, n - 1) + "…" : s

export function formatDate(value?: string) {
  const d = value ? new Date(value + "T00:00:00") : new Date()
  return d.toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
  })
}

function show(type: FormField["type"], value: string, max = 90) {
  if (type === "amount") return `₹${Number(value).toLocaleString("en-IN")}`
  if (type === "date") return formatDate(value)
  return clip(value, max)
}

export const formOf = (s: Submission) => forms.find((f) => f.name === s.form)

// Forms without a Status field count as Pending for the list filters.
export const statusOf = (s: Submission): "Paid" | "Pending" =>
  s.values.status === "Paid" ? "Paid" : "Pending"

export interface CardField {
  key: string
  label: string
  type: FormField["type"]
  /** The formatted value ("Yes" / "No" for yes-no fields). */
  text: string
}

/** Every saved field, in the order the form defines, ready to display. */
export function cardFields(s: Submission, max = 90): CardField[] {
  return (formOf(s)?.fields ?? [])
    .filter((f) => s.values[f.name])
    .map((f) => ({
      key: f.name,
      label: f.label,
      type: f.type,
      text: show(f.type, s.values[f.name], max),
    }))
}

/** A short one-line description, for the AI summaries. */
export function summaryLine(s: Submission) {
  return cardFields(s, 28)
    .filter((f) => f.key !== "status")
    .slice(0, 3)
    .map((f) => f.text)
    .join(" · ")
}
