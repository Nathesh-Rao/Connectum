import { motion, type MotionValue } from "motion/react"
import { useLoop } from "./motionKit"

const spheres = [
  { left: "62%", top: 18, size: 58, dx: 14, dy: -10, duration: 11, delay: 0 },
  { left: "14%", top: 214, size: 30, dx: -10, dy: -14, duration: 9, delay: 1.5 },
  { left: "40%", top: 30, size: 22, dx: 12, dy: 12, duration: 13, delay: 3 },
  { left: "78%", top: 238, size: 16, dx: -8, dy: -10, duration: 8, delay: 4.5 },
]

// Layered peach/apricot glow plus drifting spheres. `x` is the parallax offset,
// so the spheres trail behind the illustration and the copy.
export function OnboardingBackdrop({ x }: { x: MotionValue<number> }) {
  const loop = useLoop()
  return (
    <div className="onb-backdrop" aria-hidden="true">
      <motion.div className="onb-spheres" style={{ x }}>
        {spheres.map((s, i) => (
          <motion.span
            key={i}
            className="onb-sphere"
            style={{ left: s.left, top: s.top, width: s.size, height: s.size }}
            {...loop(
              { x: [0, s.dx, -s.dx / 2, 0], y: [0, s.dy, -s.dy / 2, 0], scale: [1, 1.1, 0.94, 1] },
              { duration: s.duration, ease: "easeInOut", repeat: Infinity, delay: s.delay },
            )}
          />
        ))}
      </motion.div>
    </div>
  )
}
