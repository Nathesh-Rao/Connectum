import { motion, useReducedMotion, type TargetAndTransition, type Transition } from "motion/react"
import { artStyle, c, SoftCard, useLoop } from "./motionKit"

const shield = "M170 74L224 94V138C224 172 202 196 170 208C138 196 116 172 116 138V94Z"
const spring = { type: "spring", stiffness: 260, damping: 18 } as const
/** Seconds after mount when the glass sweep and the message bobbing start,
 *  during the last beat of the sequence (it settles at about 3.7s). Was 3.6s
 *  for the sweep and 4s for the bob. */
const IDLE_START_DELAY = 3.4
const star = "M0-5L1.3-1.3L5 0L1.3 1.3L0 5L-1.3 1.3L-5 0L-1.3-1.3Z"
const glyphs = ["#", "7", "x", "0", "$", "%"]

const sparkles = [
  { x: 56, y: 62, delay: 0 },
  { x: 286, y: 72, delay: 1.2 },
  { x: 302, y: 214, delay: 2.4 },
  { x: 44, y: 206, delay: 0.7 },
  { x: 170, y: 26, delay: 1.9 },
]

function Bubble({ x, safe = false }: { x: number; safe?: boolean }) {
  const w = safe ? 76 : 86
  return (
    <>
      <SoftCard x={x} y={120} w={w} h={40} r={14} />
      <circle cx={x + 17} cy={140} r="8" fill={safe ? c.peach : c.apricot} stroke={c.taupe} />
      <rect x={x + 32} y="132" width={w - 46} height="6" rx="3" fill={c.olive} opacity=".7" />
      <rect x={x + 32} y="144" width={w - 56} height="5" rx="2.5" fill={c.taupe} />
      {safe && (
        <>
          <circle cx={x + w - 4} cy="122" r="8" fill={c.olive} stroke={c.ivory} strokeWidth="1.6" />
          <path d={`M${x + w - 8} 122L${x + w - 5} 125L${x + w} 118.5`} fill="none" stroke={c.ivory} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
        </>
      )}
    </>
  )
}

function Key({ angle, r }: { angle: number; r: number }) {
  const a = (angle * Math.PI) / 180
  return (
    <g transform={`translate(${r * Math.cos(a)} ${r * Math.sin(a)}) rotate(${angle + 90})`}>
      <circle r="3.2" fill={c.ivory} stroke={c.olive} strokeWidth="1.5" />
      <path d="M0 3V12M0 8H3M0 11H2.5" fill="none" stroke={c.olive} strokeWidth="1.5" strokeLinecap="round" />
    </g>
  )
}

// A message is scanned, encrypted, locked behind the shield, then re-formed.
// The sequence plays once on entry; the rings, pulses and sparkles keep idling.
export function SecurityArt() {
  const reduce = useReducedMotion()
  const loop = useLoop()
  const once = (
    initial: TargetAndTransition,
    animate: TargetAndTransition,
    transition: Transition,
  ) =>
    reduce
      ? { initial: false as const, animate, transition: { duration: 0 } }
      : { initial, animate, transition }

  return (
    <svg
      viewBox="0 0 340 270"
      role="img"
      aria-label="Security shield and lock"
      className="onb-art"
      style={artStyle}
    >
      <defs>
        <linearGradient id="onb-vault-fill" x1="0" y1="0" x2="0.4" y2="1">
          <stop offset="0" stopColor={c.apricot} />
          <stop offset="1" stopColor={c.peach} />
        </linearGradient>
        <linearGradient id="onb-vault-sweep" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor={c.ivory} stopOpacity="0" />
          <stop offset=".5" stopColor={c.ivory} stopOpacity=".75" />
          <stop offset="1" stopColor={c.ivory} stopOpacity="0" />
        </linearGradient>
        <linearGradient id="onb-vault-beam" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={c.accent} stopOpacity="0" />
          <stop offset=".5" stopColor={c.accent} />
          <stop offset="1" stopColor={c.accent} stopOpacity="0" />
        </linearGradient>
        <radialGradient id="onb-vault-halo">
          <stop offset="0" stopColor={c.peach} stopOpacity=".9" />
          <stop offset="1" stopColor={c.peach} stopOpacity="0" />
        </radialGradient>
        <clipPath id="onb-vault-shield">
          <path d={shield} />
        </clipPath>
        <clipPath id="onb-vault-lock">
          <rect x="158" y="138" width="24" height="20" rx="4" />
        </clipPath>
      </defs>

      <circle cx="170" cy="140" r="112" fill="url(#onb-vault-halo)" />
      {[0, 1, 2].map((i) => (
        <motion.circle
          key={i}
          cx="170"
          cy="140"
          r="62"
          fill="none"
          stroke={c.peach}
          strokeWidth="2.5"
          {...loop(
            { scale: [0.9, 1.5, 2], opacity: [0, 0.8, 0] },
            { duration: 4.8, repeat: Infinity, ease: "easeOut", delay: i * 1.6 },
          )}
        />
      ))}

      <g transform="translate(170 140)">
        <motion.g {...loop({ rotate: [0, 360] }, { duration: 46, repeat: Infinity, ease: "linear" })}>
          <circle r="108" fill="none" stroke={c.taupe} strokeWidth="1" strokeDasharray="2 6" />
          <Key angle={-55} r={108} />
          <circle cx="-70" cy="82" r="3" fill={c.apricot} />
          <circle cx="40" cy="-100" r="2.4" fill={c.apricot} />
        </motion.g>
        <motion.g {...loop({ rotate: [0, -360] }, { duration: 34, repeat: Infinity, ease: "linear" })}>
          <circle r="88" fill="none" stroke={c.taupe} strokeWidth="1" strokeDasharray="1 5" />
          <Key angle={195} r={88} />
          <circle cx="82" cy="30" r="2.6" fill={c.olive} />
          <circle cx="-30" cy="-82" r="2.2" fill={c.apricot} />
        </motion.g>
      </g>

      <motion.g
        {...once({ opacity: 0, scale: 0.88 }, { opacity: 1, scale: 1 }, { ...spring, delay: 0.05 })}
      >
        <path d={shield} transform="translate(0 7)" fill={c.sand} />
        <path d={shield} fill="url(#onb-vault-fill)" stroke={c.taupe} strokeWidth="2.5" strokeLinejoin="round" />
        <g transform="translate(170 141) scale(.74) translate(-170 -141)">
          <path d={shield} fill={c.ivory} stroke={c.taupe} strokeWidth="1.5" strokeLinejoin="round" opacity=".86" />
        </g>
        <path d="M118 96L170 77L222 96V110Q170 94 118 110Z" fill={c.ivory} opacity=".4" />
        <g clipPath="url(#onb-vault-shield)">
          <g transform="rotate(18 170 140)">
            <motion.rect
              x="150"
              y="50"
              width="30"
              height="180"
              fill="url(#onb-vault-sweep)"
              {...loop(
                { x: [-120, 130] },
                { duration: 1.6, repeat: Infinity, repeatDelay: 5, ease: "easeInOut", delay: IDLE_START_DELAY },
              )}
            />
          </g>
        </g>
      </motion.g>

      <motion.g
        {...once({ opacity: 0, scale: 0.6 }, { opacity: 1, scale: 1 }, { ...spring, delay: 1.8 })}
      >
        <motion.g
          {...once({ scale: 1 }, { scale: [1, 1.12, 1] }, { delay: 2.3, duration: 0.3 })}
        >
          <motion.path
            d="M163 138V131a7 7 0 0 1 14 0V138"
            fill="none"
            stroke={c.taupe}
            strokeWidth="4.5"
            strokeLinecap="round"
            {...once({ y: -6 }, { y: 0 }, { type: "spring", stiffness: 700, damping: 14, delay: 2.2 })}
          />
          <rect x="158" y="138" width="24" height="20" rx="4" fill={c.olive} />
          <circle cx="170" cy="147" r="2.6" fill={c.ivory} />
          <rect x="169" y="148" width="2" height="5" rx="1" fill={c.ivory} />
          <g clipPath="url(#onb-vault-lock)">
            <motion.path
              d="M156 140L162 140L154 158L148 158Z"
              fill={c.ivory}
              {...once({ x: 0, opacity: 0 }, { x: 34, opacity: [0, 0.9, 0] }, { delay: 2.35, duration: 0.45 })}
            />
          </g>
        </motion.g>
      </motion.g>

      <motion.circle
        cx="170"
        cy="141"
        r="60"
        fill="none"
        stroke={c.accent}
        strokeWidth="2"
        initial={{ scale: 0.8, opacity: 0 }}
        animate={reduce ? undefined : { scale: 1.7, opacity: [0, 0.55, 0] }}
        transition={{ delay: 2.55, duration: 1 }}
      />
      <motion.g {...once({ scale: 0 }, { scale: 1 }, { ...spring, delay: 2.6 })}>
        <circle cx="188" cy="162" r="11" fill={c.accent} stroke={c.ivory} strokeWidth="2" />
        <motion.path
          d="M182.5 162.5L186.5 166.5L194 157.5"
          fill="none"
          stroke={c.ivory}
          strokeWidth="2.4"
          strokeLinecap="round"
          strokeLinejoin="round"
          {...once({ pathLength: 0 }, { pathLength: 1 }, { delay: 2.75, duration: 0.35 })}
        />
      </motion.g>

      {!reduce && (
        <>
          <motion.rect
            x="116.8"
            y="80"
            width="2.4"
            height="120"
            rx="1.2"
            fill="url(#onb-vault-beam)"
            initial={{ opacity: 0, scaleY: 0.3 }}
            animate={{ opacity: [0, 1, 1, 0], scaleY: [0.3, 1, 1, 0.5] }}
            transition={{ delay: 1.1, duration: 0.9, times: [0, 0.25, 0.75, 1] }}
          />
          <motion.g
            initial={{ opacity: 0, x: -60, scale: 1 }}
            animate={{ opacity: [0, 1, 1, 0], x: [-60, 0, 0, 26], scale: [1, 1, 1, 0.85] }}
            transition={{ delay: 0.2, duration: 1.6, times: [0, 0.35, 0.6, 1], ease: "easeOut" }}
            style={{ originX: 1, originY: 0.5 }}
          >
            <Bubble x={14} />
          </motion.g>
          {glyphs.map((g, i) => (
            <motion.g
              key={g}
              initial={{ opacity: 0 }}
              animate={{ opacity: [0, 1, 0], x: [0, 14, 40], y: [0, (i - 2.5) * -3, (i - 2.5) * -6] }}
              transition={{ delay: 1.45 + i * 0.04, duration: 0.8, ease: "easeIn" }}
            >
              <text x="110" y={126 + i * 8} fontSize="9" fontWeight="700" fill={c.olive}>
                {i % 2 ? g : "·"}
              </text>
              {i % 2 === 0 && <circle cx="112" cy={125 + i * 8} r="1.8" fill={c.apricot} />}
            </motion.g>
          ))}
          {glyphs.map((g, i) => (
            <motion.g
              key={g}
              initial={{ opacity: 0 }}
              animate={{ opacity: [0, 1, 0], x: [0, 24, 44], y: [0, (i - 2.5) * 4, (i - 2.5) * 7] }}
              transition={{ delay: 3.0 + i * 0.04, duration: 0.7, ease: "easeOut" }}
            >
              <circle cx="226" cy="140" r={i % 2 ? 2.2 : 1.6} fill={i % 2 ? c.apricot : c.olive} />
            </motion.g>
          ))}
        </>
      )}

      <motion.g
        {...once(
          { opacity: 0, scale: 0.6 },
          { opacity: 1, scale: 1 },
          { ...spring, delay: 3.55 },
        )}
        style={{ originX: 0, originY: 0.5 }}
      >
        <motion.g {...loop({ y: [0, -4, 0] }, { duration: 4.4, repeat: Infinity, ease: "easeInOut", delay: IDLE_START_DELAY })}>
          <Bubble x={250} safe />
        </motion.g>
      </motion.g>

      {sparkles.map(({ x, y, delay }) => (
        <g key={x} transform={`translate(${x} ${y})`}>
          <motion.path
            d={star}
            fill={c.apricot}
            stroke={c.accent}
            strokeOpacity=".35"
            strokeWidth=".6"
            {...loop(
              { opacity: [0, 1, 0], scale: [0.4, 1.1, 0.4], y: [0, -6, -12] },
              { duration: 3.6, repeat: Infinity, ease: "easeInOut", delay },
            )}
          />
        </g>
      ))}
    </svg>
  )
}
