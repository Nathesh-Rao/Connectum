import { useState } from "react"
import { AnimatePresence, motion } from "motion/react"
import { duration, ease, useMotionPrefs } from "../../motion"
import type { Pin } from "../../state/chat-store"
import { Button } from "../Button"
import { Icon } from "../Icon"

// A summary pinned to the top of the chat. The chevron folds it down to its
// title row; the height animates (an intentional exception to transform-only).
export function PinnedSummary({
  pin,
  onUnpin,
}: {
  pin: Pin
  onUnpin: () => void
}) {
  const [open, setOpen] = useState(true)
  const { reduce, layout } = useMotionPrefs()
  const t = { duration: reduce ? duration.reduced : duration.base, ease: ease.out }
  return (
    <motion.div
      className="pinned"
      initial={{ height: 0, opacity: 0 }}
      animate={{ height: "auto", opacity: 1 }}
      exit={{ height: 0, opacity: 0 }}
      transition={t}
    >
      <div className="pinned-inner">
        <div className="pinned-head">
          <Icon name="pin" />
          <strong>{pin.title}</strong>
          <Button
            className="icon-button pinned-btn"
            aria-label="Remove pinned summary"
            onClick={onUnpin}
          >
            <Icon name="close" />
          </Button>
          <Button
            className="icon-button pinned-btn"
            aria-label={open ? "Collapse summary" : "Expand summary"}
            onClick={() => setOpen((o) => !o)}
          >
            <motion.span
              animate={{ rotate: open ? 180 : 0 }}
              transition={layout}
              style={{ display: "flex" }}
            >
              <Icon name="chevron" />
            </motion.span>
          </Button>
        </div>
        <AnimatePresence initial={false}>
          {open && (
            <motion.p
              className="pinned-text"
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: "auto", opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              transition={t}
            >
              {pin.text}
            </motion.p>
          )}
        </AnimatePresence>
      </div>
    </motion.div>
  )
}
