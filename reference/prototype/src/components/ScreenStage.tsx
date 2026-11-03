import {
  useLayoutEffect,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react"
import {
  animate,
  AnimatePresence,
  motion,
  useIsPresent,
  useMotionValue,
} from "motion/react"
import { useApp, type Screen } from "../app-state"
import {
  duration,
  ease,
  screenVariants,
  spring,
  useMotionPrefs,
  type NavCustom,
  type NavKind,
} from "../motion"
import { backOf } from "../navigation"

function ScreenFrame({
  screen,
  custom,
  children,
}: {
  screen: Screen
  custom: NavCustom
  children: ReactNode
}) {
  const { go } = useApp()
  const present = useIsPresent()
  const ref = useRef<HTMLDivElement>(null)
  // Freeze the height at mount so toggling the bottom nav can't stretch a
  // screen that is mid-transition.
  const [height, setHeight] = useState<number>()
  useLayoutEffect(() => {
    setHeight(ref.current?.parentElement?.clientHeight)
  }, [])
  const drag = useMotionValue(0)
  const target = backOf[screen]
  return (
    <motion.div
      ref={ref}
      className="screen"
      style={{
        height,
        bottom: height === undefined ? 0 : "auto",
        pointerEvents: present ? undefined : "none",
      }}
      variants={screenVariants}
      custom={custom}
      initial="enter"
      animate="center"
      exit="exit"
    >
      <motion.div className="screen-drag" style={{ x: drag }}>
        {children}
      </motion.div>
      {target && present && (
        <motion.div
          className="edge-swipe"
          onPan={(_, { offset }) => {
            if (!custom.reduce) drag.set(Math.max(0, offset.x))
          }}
          onPanEnd={(_, { offset, velocity }) => {
            if (offset.x > 80 || velocity.x > 500) go(target)
            else if (!custom.reduce) animate(drag, 0, spring)
          }}
        />
      )}
    </motion.div>
  )
}

// Hosts the screen switch. The status bar, phone frame and bottom nav live
// outside of it, so only the screens move.
export function ScreenStage({
  screen,
  kind,
  children,
}: {
  screen: Screen
  kind: NavKind
  children: ReactNode
}) {
  const { reduce } = useMotionPrefs()
  const custom: NavCustom = { kind, reduce }
  // Dims the screen that is being pushed under (or revealed again on pop).
  const scrim = useMotionValue(0)
  useEffect(() => {
    if (reduce || (kind !== "push" && kind !== "pop")) {
      scrim.set(0)
      return
    }
    const level = 0.12
    scrim.set(kind === "push" ? 0 : level)
    const controls = animate(scrim, kind === "push" ? level : 0, {
      duration: duration.page,
      ease: ease.out,
      onComplete: () => scrim.set(0),
    })
    return () => controls.stop()
  }, [screen, kind, reduce, scrim])
  return (
    <div className="screen-stage">
      <AnimatePresence initial={false} custom={custom}>
        <ScreenFrame key={screen} screen={screen} custom={custom}>
          {children}
        </ScreenFrame>
      </AnimatePresence>
      <motion.div className="screen-scrim" style={{ opacity: scrim }} />
    </div>
  )
}
