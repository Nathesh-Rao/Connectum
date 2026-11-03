import { motion } from "motion/react"
import { c, useLoop } from "./motionKit"

export type Pt = [number, number]

const sway = { originX: 0.5, originY: 1 }

// Quadratic arc between two anchors, eased by spacing the samples.
export function arcControl([ax, ay]: Pt, [bx, by]: Pt): Pt {
  return [(ax + bx) / 2, bx < ax ? -10 : Math.min(ay, by) - 26]
}
export function arcPoints(a: Pt, b: Pt) {
  const [cx, cy] = arcControl(a, b)
  return Array.from({ length: 9 }, (_, k) => {
    const s = k / 8
    const t = s * s * (3 - 2 * s)
    const u = 1 - t
    return [
      u * u * a[0] + 2 * u * t * cx + t * t * b[0],
      u * u * a[1] + 2 * u * t * cy + t * t * b[1],
    ]
  })
}

export function Plant({ x, y, tree = false, delay = 0 }: { x: number; y: number; tree?: boolean; delay?: number }) {
  const loop = useLoop()
  return (
    <g transform={`translate(${x} ${y})`}>
      <motion.g
        style={sway}
        {...loop(
          { rotate: [-2.5, 2.5, -2.5] },
          { duration: 4.5, repeat: Infinity, ease: "easeInOut", delay },
        )}
      >
        {tree ? (
          <>
            <rect x="-1.4" y="-9" width="2.8" height="9" fill={c.taupe} />
            <circle cx="0" cy="-16" r="9" fill={c.olive} />
            <circle cx="-3" cy="-19" r="4" fill={c.ivory} opacity=".25" />
          </>
        ) : (
          <>
            <circle cx="-6" cy="-3.5" r="4.5" fill={c.olive} />
            <circle cx="6" cy="-3.5" r="4.5" fill={c.olive} />
            <circle cx="0" cy="-6" r="6" fill={c.olive} />
            <circle cx="-2" cy="-8" r="2.4" fill={c.ivory} opacity=".25" />
          </>
        )}
      </motion.g>
    </g>
  )
}

export function Cloud({ x, y, s, duration }: { x: number; y: number; s: number; duration: number }) {
  const loop = useLoop()
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <motion.g {...loop({ x: [0, 16, 0] }, { duration, repeat: Infinity, ease: "easeInOut" })}>
        <ellipse cx="0" cy="5" rx="22" ry="4" fill={c.sand} opacity=".8" />
        <circle cx="-9" cy="0" r="7" fill={c.ivory} />
        <circle cx="2" cy="-4" r="9" fill={c.ivory} />
        <circle cx="12" cy="0" r="6.5" fill={c.ivory} />
      </motion.g>
    </g>
  )
}

export function Leaf({ x, y, delay }: { x: number; y: number; delay: number }) {
  const loop = useLoop()
  return (
    <g transform={`translate(${x} ${y})`}>
      <motion.path
        d="M0 0C3-4 7-4 9 0 6 4 3 4 0 0Z"
        fill={c.olive}
        {...loop(
          { x: [0, 12, -2], y: [0, 24, 46], rotate: [0, 110, 220], opacity: [0, 0.85, 0] },
          { duration: 8, repeat: Infinity, ease: "easeInOut", delay },
        )}
      />
    </g>
  )
}

