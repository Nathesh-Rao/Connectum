import { useState } from "react"
import { AnimatePresence, motion, useIsPresent } from "motion/react"
import { useApp } from "../app-state"
import { forms, type FormField } from "../data/forms"
import { duration, useMotionPrefs } from "../motion"
import { Button } from "./Button"
import { Icon } from "./Icon"
import { Landing, Rise } from "./Landing"

// A full-height form card that slides up over the chat. The chat stays
// mounted underneath, so closing it lands you right back where you were.
export function FormScreen() {
  const { formName, editId } = useApp()
  // The mode is passed down at open time, so the panel keeps its title and
  // button label while it slides away.
  return (
    <AnimatePresence>
      {formName && <FormPanel key="form" name={formName} editId={editId} />}
    </AnimatePresence>
  )
}

function Control({
  field,
  value,
  onChange,
}: {
  field: FormField
  value: string
  onChange: (v: string) => void
}) {
  if (field.type === "textarea")
    return (
      <textarea
        rows={3}
        value={value}
        placeholder={field.placeholder}
        onChange={(e) => onChange(e.target.value)}
      />
    )
  if (field.type === "select")
    return (
      <select value={value} onChange={(e) => onChange(e.target.value)}>
        <option value="">Select…</option>
        {field.options?.map((o) => <option key={o}>{o}</option>)}
      </select>
    )
  if (field.type === "yesno")
    return (
      <div className="yn-toggle">
        {["Yes", "No"].map((o) => (
          <Button
            key={o}
            type="button"
            className={"yn-opt " + o.toLowerCase() + (value === o ? " on" : "")}
            aria-pressed={value === o}
            onClick={() => onChange(value === o ? "" : o)}
          >
            {o}
          </Button>
        ))}
      </div>
    )
  return (
    <input
      type={field.type === "amount" ? "number" : field.type}
      value={value}
      placeholder={field.placeholder}
      onChange={(e) => onChange(e.target.value)}
    />
  )
}

interface FormPanelProps {
  name: string
  editId: number | null
}

function FormPanel({ name, editId }: FormPanelProps) {
  const { closeForm, submitForm, submissions } = useApp()
  const { reduce, spring, tween } = useMotionPrefs()
  const present = useIsPresent()
  const def = forms.find((f) => f.name === name)
  const editing = editId !== null
  // New: field defaults. Edit: the values saved on the submission.
  const [values, setValues] = useState<Record<string, string>>(() => {
    if (editing)
      return { ...(submissions.find((s) => s.id === editId)?.values ?? {}) }
    return Object.fromEntries(
      (def?.fields ?? [])
        .filter((f) => f.defaultValue)
        .map((f) => [f.name, f.defaultValue as string]),
    )
  })
  const [errors, setErrors] = useState<Record<string, string>>({})
  if (!def) return null

  const done = () => {
    const next: Record<string, string> = {}
    for (const f of def.fields)
      if (f.required && !(values[f.name] ?? "").trim())
        next[f.name] = "This field is required"
    setErrors(next)
    if (!Object.keys(next).length) submitForm(values)
  }

  return (
    <motion.div
      className="form-overlay"
      style={{ pointerEvents: present ? undefined : "none" }}
      initial="hidden"
      animate="shown"
      exit="hidden"
    >
      <motion.div
        className="sheet-backdrop"
        variants={{ hidden: { opacity: 0 }, shown: { opacity: 1 } }}
        transition={tween(duration.base)}
      />
      <motion.section
        className="form-screen"
        variants={{
          hidden: {
            ...(reduce ? { opacity: 0 } : { y: "100%" }),
            transition: tween(duration.page),
          },
          shown: { opacity: 1, y: 0, transition: spring },
        }}
      >
        <Landing id={"form-" + name}>
          <Rise className="form-head" index={0}>
            <Button
              className="icon-button"
              aria-label="Cancel"
              onClick={closeForm}
            >
              <Icon name="close" />
            </Button>
            <h2>{editing ? `Edit - ${def.name}` : def.name}</h2>
          </Rise>
          <div className="form-body">
            {def.fields.map((f, i) => (
              <Rise key={f.name} index={i + 1} className="form-field">
                <label htmlFor={"f-" + f.name}>
                  {f.label}
                  {f.required && <b> *</b>}
                </label>
                <div
                  className={
                    "form-control" + (errors[f.name] ? " has-error" : "")
                  }
                  id={"f-" + f.name}
                >
                  <Control
                    field={f}
                    value={values[f.name] ?? ""}
                    onChange={(v) => {
                      setValues((p) => ({ ...p, [f.name]: v }))
                      if (errors[f.name])
                        setErrors((p) => ({ ...p, [f.name]: "" }))
                    }}
                  />
                </div>
                <AnimatePresence initial={false}>
                  {errors[f.name] && (
                    <motion.small
                      className="field-error"
                      role="alert"
                      initial={{ opacity: 0, y: reduce ? 0 : -4 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0 }}
                      transition={tween(duration.fast)}
                    >
                      {errors[f.name]}
                    </motion.small>
                  )}
                </AnimatePresence>
              </Rise>
            ))}
          </div>
          <div className="form-footer">
            <Button className="primary" onClick={done}>
              {editing ? "Save" : "Done"}
            </Button>
          </div>
        </Landing>
      </motion.section>
    </motion.div>
  )
}
