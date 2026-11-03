import { useRef, useState } from "react"
import { AnimatePresence, motion } from "motion/react"
import type { Submission } from "../data/conversations"
import { cardFields, type CardField } from "../data/submissions"
import { duration, ease, spring, useMotionPrefs } from "../motion"
import { Button } from "./Button"
import { Icon } from "./Icon"
import { YesNo } from "./YesNo"

const LIMIT = 8

interface FormCardProps {
  submission: Submission
  /** True for a card that was just submitted: it flies in and pulses once. */
  fly?: boolean
  /** Bumps each time the submission is edited; the card pulses once. */
  pulse?: number
  onOpen: () => void
  /** Only cards I sent can be edited. */
  onEdit?: () => void
}

function Field({ field }: { field: CardField }) {
  return (
    <div className="sc-field">
      <small>{field.label}</small>
      {field.type === "yesno" ? (
        <YesNo value={field.text} />
      ) : (
        <b>{field.text}</b>
      )}
    </div>
  )
}

// Two columns, left filled first, with a hairline between them.
function Columns({ fields }: { fields: CardField[] }) {
  const split = Math.ceil(fields.length / 2)
  return (
    <div className="sc-cols">
      <div className="sc-col">
        {fields.slice(0, split).map((f) => (
          <Field key={f.key} field={f} />
        ))}
      </div>
      <div className="sc-col">
        {fields.slice(split).map((f) => (
          <Field key={f.key} field={f} />
        ))}
      </div>
    </div>
  )
}

// A submission rendered from its saved fields. Sent cards are mine (orange
// left border, Edit button); received cards have a green left border.
export function FormCard({
  submission: s,
  fly,
  pulse,
  onOpen,
  onEdit,
}: FormCardProps) {
  const { reduce, travel, press } = useMotionPrefs()
  const [flew] = useState(!!fly)
  const [open, setOpen] = useState(false)
  const firstPulse = useRef(pulse)
  const changed = pulse !== undefined && pulse !== firstPulse.current
  const fields = cardFields(s)
  const shown = fields.slice(0, LIMIT)
  const extra = fields.slice(LIMIT)
  const sent = s.direction === "sent"
  const t = {
    duration: reduce ? duration.reduced : duration.base,
    ease: ease.out,
  }
  return (
    <motion.div
      className={"sub-card " + (sent ? "sent" : "received")}
      role="button"
      tabIndex={0}
      onClick={onOpen}
      onKeyDown={(e) => e.key === "Enter" && onOpen()}
      initial={{
        opacity: 0,
        x: travel(sent ? 28 : -28),
        y: travel(flew ? 150 : 0),
        scale: reduce ? 1 : flew ? 0.92 : 0.98,
      }}
      animate={{ opacity: 1, x: 0, y: 0, scale: 1 }}
      transition={reduce ? { duration: duration.reduced } : spring}
      whileTap={reduce ? undefined : { scale: 0.985, transition: press }}
    >
      {flew && !reduce && (
        <motion.span
          className="fc-pulse"
          aria-hidden="true"
          initial={{ opacity: 0 }}
          animate={{ opacity: [0, 1, 0, 0.8, 0] }}
          transition={{ delay: 0.5, duration: 1.4 }}
        />
      )}
      {changed && !reduce && (
        <motion.span
          key={pulse}
          className="fc-pulse"
          aria-hidden="true"
          initial={{ opacity: 0 }}
          animate={{ opacity: [0, 1, 0, 0.7, 0] }}
          transition={{ duration: 1.3 }}
        />
      )}
      <div className="sc-strip">
        <span>Submission #{s.id}</span>
        {sent && onEdit && (
          <Button
            className="sc-edit"
            aria-label="Edit submission"
            onClick={(e: React.MouseEvent) => {
              e.stopPropagation()
              onEdit()
            }}
          >
            <Icon name="edit" />
          </Button>
        )}
      </div>
      <div className="sc-head">
        <span className="sc-icon">
          <Icon name="file" />
        </span>
        <strong className="sc-title">{s.title} submitted</strong>
      </div>
      <div className="sc-body">
        <Columns fields={shown} />
        <AnimatePresence initial={false}>
          {open && extra.length > 0 && (
            <motion.div
              key="extra"
              className="sc-extra"
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: "auto", opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              transition={t}
            >
              <Columns fields={extra} />
            </motion.div>
          )}
        </AnimatePresence>
        {extra.length > 0 && (
          <button
            className="sc-more"
            onClick={(e) => {
              e.stopPropagation()
              setOpen((o) => !o)
            }}
          >
            {open ? "Show less" : `+${extra.length} more`}
            <motion.span
              animate={{ rotate: open ? 180 : 0 }}
              transition={reduce ? { duration: 0 } : press}
              style={{ display: "flex" }}
            >
              <Icon name="chevron" />
            </motion.span>
          </button>
        )}
      </div>
      <div className="sc-time">{s.time.replace("Today at ", "")}</div>
    </motion.div>
  )
}
