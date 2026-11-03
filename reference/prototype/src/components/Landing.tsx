import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
  type ComponentType,
  type ReactNode,
} from "react"
import { motion } from "motion/react"
import { distance, duration, ease, stagger, useMotionPrefs } from "../motion"

// Screens that were already shown once this session (tab screens use `once`
// so switching back to them doesn't replay the landing).
const seen = new Set<string>()
const LandingContext = createContext({ play: true })

interface LandingProps {
  id: string
  once?: boolean
  children: ReactNode
}

/** Marks a screen's first mount; <Rise> and Button `landing` read it. */
export function Landing({ id, once = false, children }: LandingProps) {
  const [play] = useState(() => !once || !seen.has(id))
  useEffect(() => {
    seen.add(id)
  }, [id])
  return <LandingContext value={{ play }}>{children}</LandingContext>
}

// header = 0, content = 1, list rows = 2+. 40ms apart, capped at 8 rows, so
// the whole landing stays around half a second.
const lastStep = stagger.cap

/** Motion props for a staggered landing. `late` is for items that appear
 *  after the screen has settled (e.g. rows returning after a search). */
export function useLanding(index?: number | "late", rows = false) {
  const { play } = useContext(LandingContext)
  const { reduce } = useMotionPrefs()
  if (index === undefined) return {}
  if (index === "late") {
    return {
      initial: { opacity: 0, y: reduce ? 0 : distance.rise / 2 },
      animate: { opacity: 1, y: 0 },
      transition: { duration: duration.fast, ease: ease.out },
    }
  }
  if (!play) return {}
  return {
    initial: { opacity: 0, y: reduce ? 0 : distance.rise },
    animate: { opacity: 1, y: 0 },
    transition: {
      delay: Math.min(index, lastStep) * stagger.step,
      duration: rows ? duration.fast : duration.base,
      ease: ease.out,
    },
  }
}

/** True once the screen has mounted; items rendered later should animate. */
export function useSettled() {
  const settled = useRef(false)
  useEffect(() => {
    settled.current = true
  }, [])
  return settled
}

type Tag = "div" | "header" | "section" | "form" | "p" | "h2"
interface RiseProps {
  as?: Tag
  index?: number
  rows?: boolean
  [key: string]: unknown
}

/** An element that rises in on landing; renders the plain tag otherwise. */
export function Rise({
  as = "div",
  index = 0,
  rows = false,
  ...props
}: RiseProps) {
  const Component = motion[as] as ComponentType<Record<string, unknown>>
  return <Component {...useLanding(index, rows)} {...props} />
}
