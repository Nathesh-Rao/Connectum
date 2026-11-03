import { motion } from "motion/react"
import { useMotionPrefs } from "../motion"
import { useLanding } from "./Landing"

// Tappable rows get a brief tint (see .tap-row in index.css) instead of a
// scale, since they span the full width of a list.
const ROW =
  /\b(conversation|setting|enterprise-choice|enterprise-row|workspace|notification-card|receipt|detail-card|join-row|identity-strip)\b/

// `landing` staggers the button in on a screen's first mount (list rows use
// 2+ so they follow the header and content).
export function Button({
  children,
  onClick,
  className = "",
  landing,
  ...p
}: any) {
  const { reduce, press } = useMotionPrefs()
  const row = ROW.test(className)
  const rise = useLanding(landing, true)
  return (
    <motion.button
      className={row ? `${className} tap-row` : className}
      onClick={onClick}
      whileTap={row || reduce ? undefined : { scale: 0.97, transition: press }}
      {...rise}
      {...p}
    >
      {children}
    </motion.button>
  )
}
