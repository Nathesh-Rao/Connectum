import { useEffect, useMemo, useRef, useState } from "react"
import { motion, useReducedMotion } from "motion/react"
import { artStyle, c, useLive, useLoop } from "./motionKit"

type Tone = "ivory" | "peach" | "apricot" | "olive"
type Pt = [number, number]

interface Node {
  id: string
  x: number
  y: number
  r: number
  tone: Tone
  /** 0 near, 1 mid, 2 far: each layer drifts at its own slow speed. */
  layer: 0 | 1 | 2
}
interface Edge {
  a: string
  b: string
  w: number
  bend: number
  weak?: boolean
}

// "You" sits lower left; the network sprawls up and to the right, irregularly.
const YOU: Node = { id: "you", x: 86, y: 188, r: 27, tone: "ivory", layer: 0 }
const nodes: Node[] = [
  { id: "n1", x: 152, y: 148, r: 19, tone: "peach", layer: 0 },
  { id: "n2", x: 208, y: 216, r: 17, tone: "olive", layer: 0 },
  { id: "n3", x: 224, y: 106, r: 18, tone: "ivory", layer: 0 },
  { id: "m1", x: 64, y: 104, r: 14, tone: "apricot", layer: 1 },
  { id: "m2", x: 270, y: 162, r: 15, tone: "peach", layer: 1 },
  { id: "m3", x: 256, y: 56, r: 14, tone: "olive", layer: 1 },
  { id: "f1", x: 314, y: 98, r: 9, tone: "ivory", layer: 2 },
  { id: "f2", x: 160, y: 40, r: 8.5, tone: "apricot", layer: 2 },
  { id: "f3", x: 312, y: 218, r: 8.5, tone: "peach", layer: 2 },
]
const all = [YOU, ...nodes]
const byId: Record<string, Node> = Object.fromEntries(all.map((n) => [n.id, n]))
const edges: Edge[] = [
  { a: "you", b: "n1", w: 2.4, bend: 0.14 },
  { a: "you", b: "m1", w: 1.8, bend: -0.16 },
  { a: "you", b: "n2", w: 2, bend: 0.2 },
  { a: "n1", b: "n3", w: 2.1, bend: -0.12 },
  { a: "n1", b: "m2", w: 1.4, bend: 0.18 },
  { a: "n2", b: "m2", w: 1.2, bend: -0.2, weak: true },
  { a: "n3", b: "m3", w: 1.6, bend: 0.15 },
  { a: "n3", b: "f1", w: 1.1, bend: -0.18, weak: true },
  { a: "m2", b: "f3", w: 1.1, bend: 0.16, weak: true },
  { a: "m1", b: "f2", w: 1.1, bend: 0.2, weak: true },
  { a: "m3", b: "f2", w: 1.1, bend: -0.14, weak: true },
]
const NEAR = ["n1", "n2", "n3"]
// Two small groups the halo can form around.
const teams = [
  { name: "Design team", ids: ["n1", "n3", "m2"] },
  { name: "Care team", ids: ["you", "m1", "n1"] },
]
// A newcomer arrives at the left edge and links to its nearest node.
const NEWCOMER = { x: 30, y: 150, r: 11, to: "m1" }

const tones: Record<Tone, [string, string]> = {
  ivory: [c.ivory, `color-mix(in srgb, ${c.taupe} 80%, ${c.olive})`],
  peach: [c.peach, `color-mix(in srgb, ${c.apricot} 70%, ${c.accent})`],
  apricot: [c.apricot, `color-mix(in srgb, ${c.apricot} 45%, ${c.accent})`],
  olive: [`color-mix(in srgb, ${c.olive} 30%, ${c.ivory})`, c.olive],
}
const linkColor = `color-mix(in srgb, ${c.olive} 50%, ${c.taupe})`
const layerOpacity = [1, 0.92, 0.62]
const drift = [
  { dx: 3, dy: -2.5, duration: 6 },
  { dx: -2, dy: 2, duration: 9 },
  { dx: 1.4, dy: 1.2, duration: 13 },
]

// ---- geometry: curved links ----------------------------------------------
const ctrl = (e: Edge): Pt => {
  const a = byId[e.a]
  const b = byId[e.b]
  return [(a.x + b.x) / 2 - (b.y - a.y) * e.bend, (a.y + b.y) / 2 + (b.x - a.x) * e.bend]
}
const pathOf = (e: Edge) => {
  const [cx, cy] = ctrl(e)
  return `M${byId[e.a].x} ${byId[e.a].y}Q${cx} ${cy} ${byId[e.b].x} ${byId[e.b].y}`
}
const pointAt = (e: Edge, t: number): Pt => {
  const a = byId[e.a]
  const b = byId[e.b]
  const [cx, cy] = ctrl(e)
  const u = 1 - t
  return [u * u * a.x + 2 * u * t * cx + t * t * b.x, u * u * a.y + 2 * u * t * cy + t * t * b.y]
}

// Breadth-first from a node: graph distance and the order links are crossed.
function spread(origin: string) {
  const dist: Record<string, number> = { [origin]: 0 }
  const steps: { edge: Edge; from: string; to: string }[] = []
  const queue = [origin]
  while (queue.length) {
    const cur = queue.shift() as string
    for (const edge of edges) {
      const other = edge.a === cur ? edge.b : edge.b === cur ? edge.a : null
      if (other && dist[other] === undefined) {
        dist[other] = dist[cur] + 1
        steps.push({ edge, from: cur, to: other })
        queue.push(other)
      }
    }
  }
  return { dist, steps }
}

// Entry order: near first, far last; links draw and nodes spring in at the end.
const layerBase = [0.55, 1.2, 1.8]
const enterAt: Record<string, number> = { you: 0.1 }
nodes.forEach((n, i) => {
  enterAt[n.id] = layerBase[n.layer] + (i % 3) * 0.16
})
const WAVE_STEP = 0.4
/** Seconds after mount when the first message ripple (and the first newcomer
 *  cycle) begins. The network finishes growing at about 2.7s. Was: the first
 *  tick of a 3.3s interval. */
const IDLE_START_DELAY = 2.8
const RIPPLE_EVERY = 3300

function Person({ r, tone, ring = c.taupe, width = 1.2 }: { r: number; tone: Tone; ring?: string; width?: number }) {
  const [base, figure] = tones[tone]
  return (
    <>
      <circle r={r} fill={base} stroke={ring} strokeWidth={width} />
      <circle cy={-r * 0.2} r={r * 0.27} fill={figure} />
      <path
        d={`M${-r * 0.58} ${r * 0.62}Q${-r * 0.58} ${r * 0.1} 0 ${r * 0.1}Q${r * 0.58} ${r * 0.1} ${r * 0.58} ${r * 0.62}Z`}
        fill={figure}
      />
    </>
  )
}

const spring = { type: "spring", stiffness: 240, damping: 17 } as const

// Typing dots that turn into a tiny message bubble, beside the active node.
function ActiveChip({ node }: { node: Node }) {
  const loop = useLoop()
  const x = Math.min(node.x + node.r + 6, 286)
  const y = node.y - node.r - 14
  return (
    <>
      <motion.g
        initial={{ opacity: 0, scale: 0.6 }}
        animate={{ opacity: [0, 1, 1, 0], scale: [0.6, 1, 1, 0.9] }}
        transition={{ duration: 1.2, times: [0, 0.15, 0.8, 1] }}
      >
        <rect x={x} y={y + 2} width="40" height="18" rx="9" fill={c.sand} />
        <rect x={x} y={y} width="40" height="18" rx="9" fill={c.ivory} stroke={c.accent} strokeWidth="1.2" />
        {[12, 20, 28].map((cx, k) => (
          <motion.circle
            key={cx}
            cx={x + cx - 0}
            cy={y + 9}
            r="2"
            fill={c.accent}
            {...loop({ opacity: [0.35, 1, 0.35] }, { duration: 0.8, repeat: Infinity, delay: k * 0.13 })}
          />
        ))}
      </motion.g>
      <motion.g
        initial={{ opacity: 0, y: 4 }}
        animate={{ opacity: [0, 0, 1, 1, 0], y: [4, 4, 0, 0, -4] }}
        transition={{ duration: 2.3, times: [0, 0.4, 0.5, 0.86, 1] }}
      >
        <rect x={x} y={y} width="34" height="19" rx="8" fill={c.ivory} stroke={c.taupe} strokeWidth="1.1" />
        <rect x={x + 7} y={y + 5} width="20" height="3.2" rx="1.6" fill={c.accent} opacity=".8" />
        <rect x={x + 7} y={y + 11} width="13" height="3.2" rx="1.6" fill={c.taupe} />
      </motion.g>
    </>
  )
}

// A wavefront: a pulse crosses each link in turn, delayed by graph distance.
function Wave({ origin }: { origin: string }) {
  const { dist, steps } = useMemo(() => spread(origin), [origin])
  return (
    <>
      {steps.map(({ edge, from }, i) => {
        const delay = 0.35 + (dist[from] ?? 0) * WAVE_STEP
        const forward = edge.a === from
        const pts = Array.from({ length: 7 }, (_, k) => {
          const s = k / 6
          const t = s * s * (3 - 2 * s)
          return pointAt(edge, forward ? t : 1 - t)
        })
        return (
          <motion.circle
            key={i}
            r="3.4"
            fill={c.accent}
            initial={{ x: pts[0][0], y: pts[0][1], opacity: 0 }}
            animate={{
              x: pts.map((p) => p[0]),
              y: pts.map((p) => p[1]),
              opacity: [0, 1, 1, 1, 1, 1, 0],
            }}
            transition={{ delay, duration: 0.5, ease: "linear" }}
          />
        )
      })}
    </>
  )
}

// A living constellation of people on the shared backdrop.
export function ConstellationArt() {
  const reduce = useReducedMotion()
  const live = useLive()
  const loop = useLoop()
  const [wave, setWave] = useState({ id: 0, origin: "n1" })
  const started = useRef(false)

  useEffect(() => {
    if (!live) return
    const tick = () =>
      setWave((w) => {
        const options = NEAR.filter((n) => n !== w.origin)
        return { id: w.id + 1, origin: options[Math.floor(Math.random() * options.length)] }
      })
    let every: ReturnType<typeof setInterval> | undefined
    // The first ripple waits only for the network to finish growing, then
    // fires at once and repeats on the normal interval. After a pause (tab
    // hidden) it resumes immediately.
    const first = setTimeout(
      () => {
        started.current = true
        tick()
        every = setInterval(tick, RIPPLE_EVERY)
      },
      started.current ? 0 : IDLE_START_DELAY * 1000,
    )
    return () => {
      clearTimeout(first)
      clearInterval(every)
    }
  }, [live])

  const { dist } = useMemo(() => spread(wave.origin), [wave.origin])
  const farthest = Math.max(...Object.values(dist))
  const arrive = (id: string) => 0.35 + dist[id] * WAVE_STEP + 0.45
  const youAt = 0.35 + farthest * WAVE_STEP + 0.55
  const rippling = wave.id > 0 && !reduce
  const team = wave.id > 0 && wave.id % 3 === 0 ? teams[(wave.id / 3 - 1) % teams.length] : null

  const draw = (delay: number) => ({
    initial: reduce ? (false as const) : { pathLength: 0 },
    animate: { pathLength: 1 },
    transition: { delay: reduce ? 0 : delay, duration: 0.55, ease: "easeInOut" as const },
  })
  const linkDelay = (e: Edge) => Math.max(0.3, Math.max(enterAt[e.a], enterAt[e.b]) - 0.5)
  const cycle = { duration: 10, repeat: Infinity, delay: IDLE_START_DELAY, ease: "easeOut" as const }
  const target = byId[NEWCOMER.to]

  return (
    <svg
      viewBox="0 0 340 270"
      role="img"
      aria-label="A growing network of connected people"
      className="onb-art"
      style={artStyle}
    >
      <defs>
        <radialGradient id="onb-con-glow">
          <stop offset="0" stopColor={c.apricot} stopOpacity=".95" />
          <stop offset="1" stopColor={c.apricot} stopOpacity="0" />
        </radialGradient>
        <radialGradient id="onb-con-halo">
          <stop offset="0" stopColor={c.apricot} stopOpacity=".55" />
          <stop offset=".7" stopColor={c.peach} stopOpacity=".5" />
          <stop offset="1" stopColor={c.peach} stopOpacity="0" />
        </radialGradient>
      </defs>

      {/* team halo behind everything */}
      {team &&
        !reduce &&
        (() => {
          const ms = team.ids.map((id) => byId[id])
          const cx = ms.reduce((s, n) => s + n.x, 0) / ms.length
          const cy = ms.reduce((s, n) => s + n.y, 0) / ms.length
          const rx = Math.max(...ms.map((n) => Math.abs(n.x - cx) + n.r)) + 26
          const ry = Math.max(...ms.map((n) => Math.abs(n.y - cy) + n.r)) + 26
          return (
            <motion.g
              key={"halo" + wave.id}
              initial={{ opacity: 0, scale: 0.85 }}
              animate={{ opacity: [0, 1, 1, 0], scale: [0.85, 1, 1, 1.03] }}
              transition={{ duration: 3, times: [0, 0.2, 0.8, 1], delay: 0.4 }}
            >
              <ellipse cx={cx} cy={cy} rx={rx} ry={ry} fill="url(#onb-con-halo)" />
              <rect x={cx - 34} y={cy - ry - 4} width="68" height="17" rx="8.5" fill={c.ivory} stroke={c.taupe} strokeWidth="1.1" />
              <text x={cx} y={cy - ry + 8} textAnchor="middle" fontSize="8.5" fontWeight="600" fill={c.olive}>
                {team.name}
              </text>
            </motion.g>
          )
        })()}

      {/* links: curved, varied weight, some weak and dashed */}
      <g fill="none" strokeLinecap="round">
        {edges.map((e) =>
          e.weak ? (
            <motion.path
              key={e.a + e.b}
              d={pathOf(e)}
              stroke={c.taupe}
              strokeWidth={e.w}
              strokeDasharray="3 4"
              initial={reduce ? false : { opacity: 0 }}
              animate={{ opacity: 0.9 }}
              transition={{ delay: linkDelay(e), duration: 0.5 }}
            />
          ) : (
            <motion.path key={e.a + e.b} d={pathOf(e)} stroke={linkColor} strokeWidth={e.w} {...draw(linkDelay(e))} />
          ),
        )}
        {!reduce && (
          <motion.path
            d={`M${NEWCOMER.x} ${NEWCOMER.y}Q${(NEWCOMER.x + target.x) / 2 - 10} ${(NEWCOMER.y + target.y) / 2 + 6} ${target.x} ${target.y}`}
            stroke={c.accent}
            strokeWidth="1.5"
            {...loop(
              { pathLength: [0, 0, 1, 1, 0], opacity: [0, 1, 1, 1, 0] },
              { ...cycle, times: [0, 0.07, 0.15, 0.85, 1] },
            )}
          />
        )}
      </g>

      {/* the wavefront */}
      {rippling && <Wave key={"wave" + wave.id} origin={wave.origin} />}

      {/* people, by depth layer */}
      {([2, 1, 0] as const).map((layer) => (
        <motion.g
          key={layer}
          {...loop(
            { x: [0, drift[layer].dx, 0], y: [0, drift[layer].dy, 0] },
            { duration: drift[layer].duration, repeat: Infinity, ease: "easeInOut" },
          )}
          opacity={layerOpacity[layer]}
        >
          {nodes
            .filter((n) => n.layer === layer)
            .map((n) => {
              const on = wave.origin === n.id
              const blip = rippling && dist[n.id] > 0 ? arrive(n.id) : null
              return (
                <g key={n.id} transform={`translate(${n.x} ${n.y})`}>
                  <motion.g
                    initial={reduce ? false : { opacity: 0, scale: 0.3 }}
                    animate={{ opacity: 1, scale: 1 }}
                    transition={{ ...spring, delay: enterAt[n.id] }}
                  >
                    <motion.g animate={{ y: on ? -6 : 0 }} transition={spring}>
                      <motion.circle
                        r={n.r * 2.1}
                        fill="url(#onb-con-glow)"
                        initial={false}
                        animate={{ opacity: on ? 1 : 0 }}
                        transition={{ duration: 0.4 }}
                      />
                      <motion.g
                        key={"blip" + wave.id}
                        initial={{ scale: 1 }}
                        animate={blip === null ? { scale: 1 } : { scale: [1, 1.24, 1] }}
                        transition={{ delay: blip ?? 0, duration: 0.45 }}
                      >
                        <Person r={n.r} tone={n.tone} />
                        <motion.circle
                          cx={n.r * 0.72}
                          cy={n.r * 0.72}
                          r={Math.max(2.8, n.r * 0.2)}
                          fill={c.olive}
                          stroke={c.ivory}
                          strokeWidth="1.3"
                          key={"dot" + wave.id}
                          initial={reduce || wave.id > 0 ? false : { opacity: 0 }}
                          animate={
                            blip === null
                              ? { opacity: 1, scale: 1 }
                              : { opacity: [0.6, 1, 0.9], scale: [1, 1.7, 1] }
                          }
                          transition={
                            blip === null
                              ? { delay: enterAt[n.id] + 0.9, duration: 0.35 }
                              : { delay: blip, duration: 0.5 }
                          }
                        />
                      </motion.g>
                      <motion.circle
                        r={n.r + 4}
                        fill="none"
                        stroke={c.accent}
                        strokeWidth="2.2"
                        initial={false}
                        animate={{ opacity: on ? 1 : 0, scale: on ? 1 : 0.9 }}
                        transition={{ duration: 0.35 }}
                      />
                    </motion.g>
                  </motion.g>
                </g>
              )
            })}
        </motion.g>
      ))}

      {/* the newcomer drifts in from the edge, links up, and settles */}
      {!reduce && (
        <g transform={`translate(${NEWCOMER.x} ${NEWCOMER.y})`}>
          <motion.g
            {...loop(
              { opacity: [0, 1, 1, 1, 1, 0], x: [-36, -6, -6, 3, 0, 0], scale: [0.7, 1, 1, 1.06, 1, 0.8] },
              { ...cycle, times: [0, 0.07, 0.15, 0.2, 0.26, 1] },
            )}
          >
            <Person r={NEWCOMER.r} tone="apricot" />
            <motion.g {...loop({ scale: [0, 0, 1, 1, 0] }, { ...cycle, times: [0, 0.1, 0.18, 0.85, 1] })}>
              <circle cx="9" cy="-9" r="6" fill={c.accent} stroke={c.ivory} strokeWidth="1.5" />
              <path d="M9 -12V-6M6 -9H12" stroke={c.ivory} strokeWidth="1.5" strokeLinecap="round" />
            </motion.g>
          </motion.g>
        </g>
      )}

      {/* you */}
      <g transform={`translate(${YOU.x} ${YOU.y})`}>
        <motion.g
          initial={reduce ? false : { opacity: 0, scale: 0.4 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ ...spring, delay: 0.1 }}
        >
          <circle r="52" fill="url(#onb-con-glow)" />
          {rippling && (
            <motion.circle
              key={"ring" + wave.id}
              r={YOU.r + 3}
              fill="none"
              stroke={c.accent}
              strokeWidth="2"
              initial={{ opacity: 0, scale: 1 }}
              animate={{ opacity: [0, 0.7, 0], scale: [1, 1.7] }}
              transition={{ delay: youAt, duration: 0.9, ease: "easeOut" }}
            />
          )}
          <motion.g {...loop({ y: [0, -1.6, 0] }, { duration: 7, repeat: Infinity, ease: "easeInOut" })}>
            <Person r={YOU.r} tone="ivory" ring={c.accent} width={2.6} />
          </motion.g>
        </motion.g>
      </g>

      {/* the active node's typing chip and message bubble */}
      {rippling && <ActiveChip key={"chip" + wave.id} node={byId[wave.origin]} />}
    </svg>
  )
}
