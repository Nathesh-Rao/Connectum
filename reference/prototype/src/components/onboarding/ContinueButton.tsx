import type { ReactNode } from "react"
import { motion } from "motion/react"
import { useLoop } from "./motionKit"

// Primary button with a spring press and a soft sheen that sweeps across it.
export function ContinueButton({
  onClick,
  children,
}: {
  onClick: () => void
  children: ReactNode
}) {
  const loop = useLoop()
  return (
    <motion.button
      className="primary onb-continue"
      onClick={onClick}
      whileTap={{ scale: 0.97 }}
      transition={{ type: "spring", stiffness: 500, damping: 30 }}
    >
      {children}
      <motion.span
        className="onb-sheen"
        aria-hidden="true"
        {...loop(
          { x: ["-120%", "420%"] as unknown as number[] },
          { duration: 0.9, ease: "easeInOut", repeat: Infinity, repeatDelay: 3.6, delay: 1.5 },
        )}
      />
    </motion.button>
  )
}
