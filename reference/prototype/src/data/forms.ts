export interface FormField {
  name: string
  label: string
  type: "text" | "textarea" | "date" | "amount" | "select" | "yesno"
  required?: boolean
  placeholder?: string
  options?: string[]
  defaultValue?: string
}

export interface FormDef {
  name: string
  fields: FormField[]
}

const yesno = (name: string, label: string): FormField => ({
  name,
  label,
  type: "yesno",
})
const amount: FormField = {
  name: "amount",
  label: "Amount",
  type: "amount",
  placeholder: "₹ 0",
}
const visit: FormField = { name: "date", label: "Visit date", type: "date" }
const status: FormField = {
  name: "status",
  label: "Status",
  type: "select",
  options: ["Pending", "Paid"],
  defaultValue: "Pending",
}

// Field order is the card's order: the card fills its left column first.
export const forms: FormDef[] = [
  {
    name: "Advice & review",
    fields: [
      {
        name: "diet",
        label: "Diet advice",
        type: "text",
        placeholder: "Diet advice",
      },
      {
        name: "general",
        label: "General advice",
        type: "text",
        placeholder: "General advice",
      },
      {
        name: "message",
        label: "Message",
        type: "text",
        placeholder: "Message to the patient",
      },
      yesno("physio", "Physiotherapy required"),
      yesno("surgery", "Surgery required"),
      yesno("dietician", "Dietician counselling required"),
      yesno("ip", "IP required"),
      {
        name: "patient",
        label: "Patient",
        type: "text",
        required: true,
        placeholder: "Patient name",
      },
      {
        name: "review",
        label: "Review",
        type: "select",
        options: ["Review not required", "1 week", "2 weeks", "1 month"],
      },
    ],
  },
  {
    name: "Clinical examination - Ortho",
    fields: [
      {
        name: "area",
        label: "Affected area",
        type: "text",
        required: true,
        placeholder: "e.g. Left knee",
      },
      {
        name: "general",
        label: "General examination",
        type: "textarea",
        placeholder: "Findings",
      },
      {
        name: "tests",
        label: "Tests",
        type: "textarea",
        placeholder: "Tests performed",
      },
      {
        name: "department",
        label: "Department",
        type: "text",
        defaultValue: "Ortho",
      },
      visit,
      yesno("followUp", "Follow-up required"),
      amount,
      status,
    ],
  },
  {
    name: "Diagnosis",
    fields: [
      {
        name: "diagnosis",
        label: "Diagnosis",
        type: "text",
        required: true,
        placeholder: "Primary diagnosis",
      },
      {
        name: "notes",
        label: "Notes",
        type: "textarea",
        placeholder: "Additional notes",
      },
      visit,
      yesno("chronic", "Chronic condition"),
      status,
    ],
  },
  {
    name: "Diagnosis test",
    fields: [
      {
        name: "test",
        label: "Test name",
        type: "text",
        required: true,
        placeholder: "e.g. X-ray",
      },
      {
        name: "result",
        label: "Result",
        type: "textarea",
        placeholder: "Result summary",
      },
      visit,
      yesno("urgent", "Report urgent"),
      amount,
      status,
    ],
  },
  {
    name: "Doctor appointment",
    fields: [
      { name: "date", label: "Appointment date", type: "date", required: true },
      {
        name: "doctor",
        label: "Doctor",
        type: "text",
        placeholder: "Dr. name",
      },
      {
        name: "reason",
        label: "Reason",
        type: "textarea",
        placeholder: "Reason for visit",
      },
      yesno("tele", "Teleconsultation"),
      status,
    ],
  },
  {
    name: "Prescribe lab test",
    fields: [
      {
        name: "test",
        label: "Test",
        type: "text",
        required: true,
        placeholder: "e.g. Blood count",
      },
      {
        name: "instructions",
        label: "Instructions",
        type: "textarea",
        placeholder: "Timing, preparation…",
      },
      yesno("fasting", "Fasting required"),
      amount,
      status,
    ],
  },
  {
    name: "Prescribe medicine",
    fields: [
      {
        name: "medicine",
        label: "Medicine",
        type: "text",
        required: true,
        placeholder: "Name and strength",
      },
      {
        name: "dosage",
        label: "Dosage",
        type: "text",
        required: true,
        placeholder: "e.g. 1 tablet twice daily",
      },
      {
        name: "duration",
        label: "Duration",
        type: "select",
        options: ["3 days", "5 days", "1 week", "2 weeks"],
      },
      yesno("refill", "Refill allowed"),
      amount,
      status,
    ],
  },
  {
    name: "Referral",
    fields: [
      {
        name: "to",
        label: "Refer to",
        type: "text",
        required: true,
        placeholder: "Specialist or hospital",
      },
      {
        name: "reason",
        label: "Reason",
        type: "textarea",
        required: true,
        placeholder: "Why is this referral needed?",
      },
      yesno("urgent", "Urgent"),
      status,
    ],
  },
  {
    name: "Treatment plan",
    fields: [
      {
        name: "plan",
        label: "Plan",
        type: "textarea",
        required: true,
        placeholder: "Steps of the treatment",
      },
      {
        name: "duration",
        label: "Duration",
        type: "select",
        options: ["2 weeks", "4 weeks", "8 weeks"],
      },
      yesno("physio", "Physiotherapy required"),
      amount,
      status,
    ],
  },
]

export const MY_SUBMISSIONS = "My Submissions"
export const initialRecentForms = [
  "Clinical examination - Ortho",
  "Prescribe medicine",
  "Referral",
]
