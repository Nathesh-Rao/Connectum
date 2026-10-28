import { motion } from "motion/react"
import { useMotionPrefs } from "../motion"
import { Button } from "./Button"
import { useLanding } from "./Landing"

interface Chip {
  label: string
  badge?: string
}

interface FilterChipsProps {
  id: string
  items: Chip[]
  value: string
  onChange: (value: string) => void
  landing?: number
}

// Tabs with a selection indicator that slides between chips.
export function FilterChips({
  id,
  items,
  value,
  onChange,
  landing,
}: FilterChipsProps) {
  const { layout } = useMotionPrefs()
  return (
    <motion.div className="filters" {...useLanding(landing)}>
      {items.map(({ label, badge }) => (
        <Button
          key={label}
          className={value === label ? "selected" : ""}
          onClick={() => onChange(label)}
        >
          {label}
          {badge && <span>{badge}</span>}
          {value === label && (
            <motion.i
              className="chip-indicator"
              layoutId={`chip-${id}`}
              transition={layout}
            />
          )}
        </Button>
      ))}
    </motion.div>
  )
}
