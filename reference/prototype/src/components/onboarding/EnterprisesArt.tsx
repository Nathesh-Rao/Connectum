import { useEffect, useMemo, useRef, useState, type ReactNode } from "react"
import { motion, useReducedMotion } from "motion/react"
import { artStyle, c, useLive, useLoop } from "./motionKit"
import { arcControl, arcPoints, Cloud, Leaf, Plant, type Pt } from "./sceneKit"

type Win = [number, number, number, number]

const GROUND = 205
/** Seconds after mount when the first active building lifts and the pin makes
 *  its first hop. Buildings and windows are up at about 2.3s. Was: a 2.3s
 *  interval whose first tick only lifted building 0 (pin hopped at 4.6s). */
const IDLE_START_DELAY = 2.3
const HOP_EVERY = 2300
const spring = { type: "spring", stiffness: 260, damping: 18 } as const

const buildings = [
  { name: "Agile Labs", box: { x: 20, y: 141, w: 80, h: 64 }, anchor: [60, 124] as Pt },
  { name: "Demo HR", box: { x: 106, y: 59, w: 68, h: 146 }, anchor: [140, 42] as Pt },
  { name: "Kauvery Hospital", box: { x: 178, y: 107, w: 88, h: 98 }, anchor: [222, 90] as Pt },
  { name: "Demo University", box: { x: 268, y: 107, w: 60, h: 98 }, anchor: [298, 88] as Pt },
]
const towerWindows: Win[] = [76, 94, 112, 130, 148, 166].flatMap((y) =>
  [120, 133, 146].map((x): Win => [x, y, 8, 10]),
)
const clinicWindows: Win[] = [150, 170].flatMap((y) =>
  [192, 210, 228].map((x): Win => [x, y, 10, 12]),
)
const windows: Win[][] = [
  [[64, 168, 8, 11], [76, 168, 8, 11]],
  towerWindows,
  clinicWindows,
  [[282, 146, 9, 12], [297, 146, 9, 12], [282, 166, 9, 12], [297, 166, 9, 12]],
]
const windowStart = windows.map((_, i) => windows.slice(0, i).reduce((n, w) => n + w.length, 0))

const routes = buildings.slice(1).map((b, i) => {
  const a = buildings[i].anchor
  const [cx, cy] = arcControl(a, b.anchor)
  return `M${a[0]} ${a[1]}Q${cx} ${cy} ${b.anchor[0]} ${b.anchor[1]}`
})

function Windows({ list, start, reduce }: { list: Win[]; start: number; reduce: boolean | null }) {
  return list.map(([x, y, w, h], k) => (
    <g key={k}>
      <rect x={x} y={y} width={w} height={h} rx="1.5" fill={c.sand} />
      <motion.g
        initial={reduce ? false : { opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.9 + (start + k) * 0.04, duration: 0.35 }}
      >
        <rect x={x - 2} y={y - 2} width={w + 4} height={h + 4} rx="3" fill={c.apricot} opacity=".4" />
        <rect x={x} y={y} width={w} height={h} rx="1.5" fill={c.apricot} />
      </motion.g>
    </g>
  ))
}

function Building({
  index,
  on,
  reduce,
  children,
}: {
  index: number
  on: boolean
  reduce: boolean | null
  children: ReactNode
}) {
  const { x, y, w, h } = buildings[index].box
  return (
    <motion.g
      initial={reduce ? false : { y: h + 30 }}
      animate={{ y: 0 }}
      transition={{ type: "spring", stiffness: 120, damping: 14, delay: 0.15 + index * 0.3 }}
    >
      <motion.g animate={{ y: on ? -8 : 0 }} transition={spring}>
        <motion.ellipse
          cx={x + w / 2}
          cy={y + h / 2}
          rx={w * 0.8}
          ry={h * 0.62}
          fill="url(#onb-city-glow)"
          initial={false}
          animate={{ opacity: on ? 1 : 0 }}
          transition={{ duration: 0.4 }}
        />
        {children}
        <motion.rect
          x={x}
          y={y}
          width={w}
          height={h}
          rx="7"
          fill="none"
          stroke={c.accent}
          strokeWidth="2"
          initial={false}
          animate={{ opacity: on ? 1 : 0, scale: on ? 1 : 0.97 }}
          transition={{ duration: 0.35 }}
        />
      </motion.g>
    </motion.g>
  )
}

// A miniature skyline. Each building takes a turn as the active enterprise.
export function EnterprisesArt() {
  const reduce = useReducedMotion()
  const live = useLive()
  const [active, setActive] = useState(reduce ? 1 : -1)
  const previous = useRef(0)
  const started = useRef(false)

  useEffect(() => {
    if (!live) return
    const tick = () =>
      setActive((a) => (a < 0 ? 1 : (a + 1) % buildings.length))
    let every: ReturnType<typeof setInterval> | undefined
    // The first cycle starts as the entry finishes and already hops (the pin
    // starts on building 0, so building 1 is first), then repeats normally.
    const first = setTimeout(
      () => {
        started.current = true
        tick()
        every = setInterval(tick, HOP_EVERY)
      },
      started.current ? 0 : IDLE_START_DELAY * 1000,
    )
    return () => {
      clearTimeout(first)
      clearInterval(every)
    }
  }, [live])

  const hop = useMemo(
    () => arcPoints(buildings[previous.current].anchor, buildings[Math.max(active, 0)].anchor),
    [active],
  )
  useEffect(() => {
    previous.current = Math.max(active, 0)
  }, [active])

  return (
    <svg
      viewBox="0 0 340 270"
      role="img"
      aria-label="Multiple connected enterprise buildings"
      className="onb-art"
      style={artStyle}
    >
      <defs>
        <radialGradient id="onb-city-glow">
          <stop offset="0" stopColor={c.apricot} stopOpacity=".85" />
          <stop offset="1" stopColor={c.apricot} stopOpacity="0" />
        </radialGradient>
        <clipPath id="onb-city-clip">
          <rect x="0" y="0" width="340" height={GROUND + 1} />
        </clipPath>
      </defs>

      <Cloud x={52} y={40} s={0.8} duration={11} />
      <Cloud x={262} y={34} s={1} duration={13} />
      <Cloud x={176} y={24} s={0.6} duration={9} />

      <ellipse cx="170" cy={GROUND + 6} rx="160" ry="9" fill={c.sand} />
      <rect x="8" y={GROUND} width="324" height="3.5" rx="1.75" fill={c.taupe} />

      <g clipPath="url(#onb-city-clip)">
        <Building index={0} on={active === 0} reduce={reduce}>
          <path d="M22 156L34 142H98V156Z" fill={c.sand} stroke={c.taupe} strokeWidth="1.2" strokeLinejoin="round" />
          <rect x="24" y="155" width="72" height="50" fill={c.ivory} stroke={c.taupe} strokeWidth="1.2" />
          <rect x="84" y="156" width="11" height="48" fill={c.sand} />
          <rect x="34" y="178" width="26" height="27" fill={c.sand} stroke={c.taupe} />
          <path d="M34 186H60M34 193H60M34 200H60" stroke={c.taupe} />
          <Windows list={windows[0]} start={windowStart[0]} reduce={reduce} />
          <Plant x={88} y={142} delay={0.6} />
        </Building>

        <Building index={1} on={active === 1} reduce={reduce}>
          <rect x="112" y="65" width="56" height="140" fill={c.ivory} stroke={c.taupe} strokeWidth="1.2" />
          <rect x="156" y="66" width="11" height="138" fill={c.sand} />
          <rect x="108" y="59" width="64" height="7" rx="2" fill={c.sand} stroke={c.taupe} strokeWidth="1.2" />
          <rect x="132" y="186" width="16" height="19" fill={c.sand} stroke={c.taupe} />
          <Windows list={windows[1]} start={windowStart[1]} reduce={reduce} />
          <Plant x={162} y={59} delay={1.1} />
        </Building>

        <Building index={2} on={active === 2} reduce={reduce}>
          <rect x="184" y="113" width="76" height="92" fill={c.ivory} stroke={c.taupe} strokeWidth="1.2" />
          <rect x="245" y="114" width="14" height="90" fill={c.sand} />
          <rect x="180" y="107" width="84" height="7" rx="2" fill={c.sand} stroke={c.taupe} strokeWidth="1.2" />
          <circle cx="222" cy="130" r="10" fill={c.peach} stroke={c.taupe} />
          <path d="M222 124V136M216 130H228" stroke={c.accent} strokeWidth="3.5" strokeLinecap="round" />
          <rect x="216" y="187" width="16" height="18" fill={c.sand} stroke={c.taupe} />
          <Windows list={windows[2]} start={windowStart[2]} reduce={reduce} />
          <Plant x={196} y={107} delay={0.4} />
          <Plant x={250} y={107} delay={1.4} />
        </Building>

        <Building index={3} on={active === 3} reduce={reduce}>
          <path d="M270 130L298 108L326 130Z" fill={c.sand} stroke={c.taupe} strokeWidth="1.2" strokeLinejoin="round" />
          <rect x="274" y="130" width="48" height="75" fill={c.ivory} stroke={c.taupe} strokeWidth="1.2" />
          <rect x="311" y="131" width="10" height="73" fill={c.sand} />
          <rect x="290" y="188" width="14" height="17" rx="7" fill={c.sand} stroke={c.taupe} />
          <Windows list={windows[3]} start={windowStart[3]} reduce={reduce} />
        </Building>
        {[104, 176, 267].map((x, i) => (
          <motion.g
            key={x}
            initial={reduce ? false : { y: 34 }}
            animate={{ y: 0 }}
            transition={{ type: "spring", stiffness: 140, damping: 14, delay: 1 + i * 0.15 }}
          >
            <Plant x={x} y={GROUND} tree delay={i * 0.8} />
          </motion.g>
        ))}
      </g>

      {routes.map((d, i) => (
        <motion.path
          key={i}
          d={d}
          fill="none"
          stroke={c.accent}
          strokeWidth="1.6"
          strokeLinecap="round"
          initial={reduce ? false : { pathLength: 0 }}
          animate={{ pathLength: 1 }}
          transition={{ delay: 1.3 + i * 0.35, duration: 0.6, ease: "easeInOut" }}
        />
      ))}
      {buildings.map(({ anchor: [x, y] }, i) => (
        <motion.circle
          key={i}
          cx={x}
          cy={y}
          r="3"
          fill={c.ivory}
          stroke={c.accent}
          strokeWidth="1.6"
          initial={reduce ? false : { scale: 0 }}
          animate={{ scale: 1 }}
          transition={{ ...spring, delay: 1.3 + i * 0.35 }}
        />
      ))}

      {buildings.map(({ name, anchor: [x, y] }, i) => {
        const width = name.length * 5.3 + 18
        const cx = Math.min(Math.max(x, width / 2 + 4), 336 - width / 2)
        const on = active === i
        return (
          <motion.g
            key={name}
            initial={false}
            animate={{ opacity: on ? 1 : 0, scale: on ? 1 : 0.6, y: on ? -8 : 0 }}
            transition={spring}
          >
            <rect x={cx - width / 2} y={y - 30} width={width} height="17" rx="8.5" fill={c.sand} transform="translate(0 2.5)" />
            <rect x={cx - width / 2} y={y - 30} width={width} height="17" rx="8.5" fill={c.ivory} stroke={c.accent} strokeWidth="1.2" />
            <text x={cx} y={y - 18.2} textAnchor="middle" fontSize="9" fontWeight="600" fill={c.olive}>
              {name}
            </text>
          </motion.g>
        )
      })}

      <motion.g
        initial={reduce ? false : { scale: 0, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ ...spring, delay: 1.9 }}
      >
        <motion.g
          initial={{ x: hop[0][0], y: hop[0][1] }}
          animate={{ x: hop.map((p) => p[0]), y: hop.map((p) => p[1]) }}
          transition={{ duration: reduce ? 0 : 0.75, ease: "linear" }}
        >
          <circle r="7" fill={c.accent} opacity=".25" />
          <circle r="5" fill={c.accent} stroke={c.ivory} strokeWidth="1.6" />
          <circle r="1.6" fill={c.ivory} />
        </motion.g>
      </motion.g>

      <Leaf x={70} y={130} delay={0} />
      <Leaf x={176} y={150} delay={1.2} />
      <Leaf x={198} y={96} delay={IDLE_START_DELAY} />
      <Leaf x={252} y={96} delay={1.5} />
    </svg>
  )
}
