import { useEffect, useState } from "react"
import { useReducedMotion, type Transition } from "motion/react"

// Palette tokens live in src/index.css; SVG attributes resolve them at paint time.
export const c = {
  ivory: "var(--ivory)",
  peach: "var(--peach)",
  apricot: "var(--apricot)",
  sand: "var(--sand)",
  olive: "var(--olive)",
  taupe: "var(--taupe)",
  accent: "var(--accent)",
}

// Inline size beats the global `svg{width:22px;height:22px}` reset.
export const artStyle = {
  width: 340,
  height: "auto",
  aspectRatio: "340 / 270",
  maxWidth: "100%",
  maxHeight: "100%",
} as const

export function usePageVisible() {
  const [visible, setVisible] = useState(() => !document.hidden)
  useEffect(() => {
    const update = () => setVisible(!document.hidden)
    document.addEventListener("visibilitychange", update)
    return () => document.removeEventListener("visibilitychange", update)
  }, [])
  return visible
}

// False while the tab is hidden or the user prefers reduced motion.
export function useLive() {
  const reduce = useReducedMotion()
  return usePageVisible() && !reduce
}

// Props for an idle loop. Keyframes should start at the resting value, so
// a paused or reduced-motion element simply sits at its first keyframe.
export function useLoop() {
  const live = useLive()
  return (keyframes: Record<string, number[]>, transition: Transition) => {
    const rest = Object.fromEntries(
      Object.entries(keyframes).map(([key, values]) => [key, values[0]]),
    )
    return {
      initial: rest,
      animate: live ? keyframes : rest,
      transition: live ? transition : { duration: 0 },
    }
  }
}

// Ivory card with two stacked sand shadows.
export function SoftCard({
  x,
  y,
  w,
  h,
  r = 18,
  fill = c.ivory,
  stroke = c.taupe,
}: {
  x: number
  y: number
  w: number
  h: number
  r?: number
  fill?: string
  stroke?: string
}) {
  return (
    <>
      <rect x={x - 3} y={y + 11} width={w + 6} height={h} rx={r} fill={c.sand} opacity=".55" />
      <rect x={x} y={y + 5} width={w} height={h} rx={r} fill={c.sand} />
      <rect x={x} y={y} width={w} height={h} rx={r} fill={fill} stroke={stroke} strokeWidth="1.2" />
    </>
  )
}
