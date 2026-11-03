import { useReducedMotion, type Transition, type Variants } from "motion/react"

// ---- Tokens --------------------------------------------------------------
// Only transform and opacity are animated. Durations are in seconds.
export const duration = {
  fast: 0.19,
  base: 0.32,
  slow: 0.5,
  page: 0.45, // push / pop screen travel (the outgoing parallax shares it)
  reduced: 0.15, // reduced motion: short fades only, unchanged
} as const

type Bezier = [number, number, number, number]
export const ease: Record<"out" | "in" | "inOut", Bezier> = {
  // Expo-style settle with a gentle start, so movement doesn't jerk off.
  out: [0.25, 0.06, 0.12, 1],
  in: [0.4, 0, 1, 1],
  inOut: [0.65, 0, 0.35, 1],
}

// Sheets, panels, forms and cards: a visible settle that isn't bouncy.
export const spring: Transition = {
  type: "spring",
  stiffness: 300,
  damping: 32,
  mass: 1,
}

// Micro-interactions (button press, chip and tab indicators, dots, send
// morph) keep the original snappy spring.
export const press: Transition = {
  type: "spring",
  stiffness: 420,
  damping: 34,
  mass: 1,
}

export const distance = {
  rise: 12, // landing / list rows
  tab: 8, // tab crossfade
  parallax: 25, // % the outgoing screen shifts on push
} as const

export const stagger = { step: 0.055, cap: 8 } as const

/** Reduced motion: travel and scale collapse into short fades. */
export function useMotionPrefs() {
  const reduce = !!useReducedMotion()
  return {
    reduce,
    tween: (d: number = duration.base): Transition => ({
      duration: reduce ? duration.reduced : d,
      ease: ease.out,
    }),
    spring: reduce
      ? { duration: duration.reduced, ease: ease.out } as Transition
      : spring,
    /** The snappy spring for presses and indicators. */
    press: reduce
      ? { duration: duration.reduced, ease: ease.out } as Transition
      : press,
    /** For layout / layoutId moves: instant when motion is reduced. */
    layout: reduce ? { duration: 0 } as Transition : press,
    /** Pixels of travel, or 0 when the user prefers reduced motion. */
    travel: (px: number) => (reduce ? 0 : px),
  }
}

// ---- Onboarding slides ---------------------------------------------------
// Direction is +1 when moving forward (new slide enters from the right).
// Parallax: copy travels furthest, the illustration less, the backdrop least.
export const copyVariants = {
  enter: (direction: number) => ({ x: `${direction * 100}%` }),
  center: { x: 0 },
  exit: (direction: number) => ({ x: `${direction * -100}%` }),
}
export const artVariants = {
  enter: (direction: number) => ({ x: `${direction * 75}%`, opacity: 0 }),
  center: { x: 0, opacity: 1 },
  exit: (direction: number) => ({ x: `${direction * -75}%`, opacity: 0 }),
}
export const fadeVariants = {
  enter: { opacity: 0 },
  center: { opacity: 1 },
  exit: { opacity: 0 },
}

// ---- Screen navigation ---------------------------------------------------
// push/pop travel horizontally with parallax; intro, enter, tab and fade are
// crossfades. z-index keeps the right screen on top for each direction.
export type NavKind = "push" | "pop" | "intro" | "enter" | "tab" | "fade"
export interface NavCustom {
  kind: NavKind
  reduce: boolean
}

const LOW = 10
const HIGH = 30
const instantZ = { zIndex: { duration: 0 } }
const out = (d: number): Transition => ({ duration: d, ease: ease.out })

export const screenVariants: Variants = {
  enter: ({ kind, reduce }: NavCustom) => {
    if (reduce) return { opacity: 0, zIndex: kind === "pop" ? LOW : HIGH }
    switch (kind) {
      case "push":
        return { x: "100%", zIndex: HIGH }
      case "pop":
        return { x: `-${distance.parallax}%`, zIndex: LOW }
      case "intro":
        return { opacity: 0, scale: 1.02, zIndex: HIGH }
      case "enter":
        return { opacity: 0, y: 16, zIndex: LOW }
      case "tab":
        return { opacity: 0, y: distance.tab, zIndex: HIGH }
      default:
        return { opacity: 0, zIndex: HIGH }
    }
  },
  center: ({ kind, reduce }: NavCustom) => {
    if (reduce) return { opacity: 1, transition: out(duration.reduced) }
    switch (kind) {
      case "push":
      case "pop":
        return { x: 0, transition: out(duration.page) }
      case "intro":
      case "enter":
        return { opacity: 1, scale: 1, y: 0, transition: out(duration.slow) }
      default:
        return { opacity: 1, y: 0, transition: out(duration.base) }
    }
  },
  exit: ({ kind, reduce }: NavCustom) => {
    if (reduce)
      return {
        opacity: 0,
        zIndex: kind === "pop" ? HIGH : LOW,
        transition: { ...out(duration.reduced), ...instantZ },
      }
    switch (kind) {
      case "push":
        return {
          x: `-${distance.parallax}%`,
          zIndex: LOW,
          transition: { x: out(duration.page), ...instantZ },
        }
      case "pop":
        return {
          x: "100%",
          zIndex: HIGH,
          transition: { x: out(duration.page), ...instantZ },
        }
      case "intro":
        return {
          opacity: 0,
          zIndex: LOW,
          transition: { opacity: out(duration.slow), ...instantZ },
        }
      case "enter":
        return {
          opacity: 0,
          zIndex: HIGH,
          transition: { opacity: out(duration.base), ...instantZ },
        }
      default:
        return {
          opacity: 0,
          zIndex: LOW,
          transition: { opacity: out(duration.fast), ...instantZ },
        }
    }
  },
}
