import { useEffect, useRef, useState } from "react"
import {
  animate,
  AnimatePresence,
  motion,
  useMotionValue,
  useReducedMotion,
  useTransform,
  type PanInfo,
} from "motion/react"
import { useApp } from "../app-state"
import { Button } from "../components/Button"
import { Icon } from "../components/Icon"
import { ContinueButton } from "../components/onboarding/ContinueButton"
import { ConstellationArt } from "../components/onboarding/ConstellationArt"
import { EnterprisesArt } from "../components/onboarding/EnterprisesArt"
import { OnboardingBackdrop } from "../components/onboarding/OnboardingBackdrop"
import { SecurityArt } from "../components/onboarding/SecurityArt"
import {
  artVariants,
  copyVariants,
  duration,
  ease,
  fadeVariants,
  press,
  spring,
} from "../motion"

const onboardingArt = [ConstellationArt, EnterprisesArt, SecurityArt]

function Introduction({ step, setStep, onFinish }: any) {
  const reduce = useReducedMotion()
  const [direction, setDirection] = useState(1)
  const first = useRef(true)
  useEffect(() => {
    first.current = false
  }, [])
  const go = (next: number) => {
    if (next === step || next < 0 || next > 2) return
    setDirection(next > step ? 1 : -1)
    setStep(next)
  }
  // One pan value drives every layer at a different rate.
  const pan = useMotionValue(0)
  const artX = useTransform(pan, (v) => v * 0.8)
  const stepShift = useMotionValue(0)
  const backdropX = useTransform(
    [stepShift, pan],
    ([shift, drag]: number[]) => shift + drag * 0.35,
  )
  useEffect(() => {
    const target = -step * 60
    if (reduce) stepShift.set(target)
    else animate(stepShift, target, { duration: duration.page, ease: ease.out })
  }, [step, reduce, stepShift])
  const gestures = {
    onPan: (_: unknown, { offset }: PanInfo) => {
      if (reduce) return
      const atEdge =
        (offset.x > 0 && step === 0) || (offset.x < 0 && step === 2)
      pan.set(offset.x * (atEdge ? 0.25 : 1))
    },
    onPanEnd: (_: unknown, { offset, velocity }: PanInfo) => {
      if (offset.x < -50 || velocity.x < -500) go(step + 1)
      else if (offset.x > 50 || velocity.x > 500) go(step - 1)
      if (!reduce) animate(pan, 0, spring)
    },
  }
  const slide = (variants: typeof copyVariants | typeof artVariants) => ({
    custom: direction,
    variants: reduce ? fadeVariants : variants,
    initial: first.current ? false as const : "enter",
    animate: "center",
    exit: "exit",
    transition: {
      duration: reduce ? duration.reduced : duration.page,
      ease: ease.out,
    },
  })
  const rise = (order: number) => ({
    initial: reduce ? false as const : { opacity: 0, y: 12 },
    animate: { opacity: 1, y: 0 },
    transition: {
      delay: 0.12 + order * 0.06,
      duration: duration.slow,
      ease: ease.out,
    },
  })
  const Art = onboardingArt[step]
  const titles = [
    "All your conversations in one place",
    "Work across multiple enterprises",
    "Secure, simple and ready to go",
  ]
  const copy = [
    "Stay connected with your teams, projects and ideas.",
    "Switch, collaborate and keep everything organised.",
    "Your data and conversations stay protected.",
  ]
  return (
    <section className="introduction">
      <div className="introduction-top">
        <span className="access-wordmark">
          <img src="/connectum-logo.png" alt="" />
          Connectum
        </span>
        <Button onClick={onFinish}>Skip</Button>
      </div>
      <div className={"intro-illustration illustration-" + step}>
        <OnboardingBackdrop x={backdropX} />
        <motion.div className="intro-art-gesture" {...gestures}>
          <motion.div className="intro-art-layer" style={{ x: artX }}>
            <AnimatePresence custom={direction}>
              <motion.div
                key={step}
                className="intro-slide"
                {...slide(artVariants)}
              >
                <Art />
              </motion.div>
            </AnimatePresence>
          </motion.div>
        </motion.div>
      </div>
      <div className="intro-content">
        <div className="pagination" aria-label={`Step ${step + 1} of 3`}>
          {titles.map((_, i) => (
            <Button
              key={i}
              aria-label={`Onboarding ${i + 1}`}
              className={i === step ? "active" : ""}
              onClick={() => go(i)}
            >
              <motion.span
                layout
                style={{ width: i === step ? 20 : 5, borderRadius: 4 }}
                transition={reduce ? { duration: 0 } : press}
              />
            </Button>
          ))}
        </div>
        <motion.div className="intro-copy" {...gestures}>
          <motion.div className="intro-copy-layer" style={{ x: pan }}>
            <AnimatePresence custom={direction}>
              <motion.div
                key={step}
                className="intro-copy-slide"
                {...slide(copyVariants)}
              >
                <motion.h2 {...rise(0)}>{titles[step]}</motion.h2>
                <motion.p {...rise(1)}>{copy[step]}</motion.p>
              </motion.div>
            </AnimatePresence>
          </motion.div>
        </motion.div>
        <ContinueButton onClick={() => (step < 2 ? go(step + 1) : onFinish())}>
          {step === 2 ? "Get Started" : "Continue"}
          <Icon name="arrow" />
        </ContinueButton>
        <div className="intro-bottom">
          {step > 0 ? (
            <Button onClick={() => go(step - 1)}>Back</Button>
          ) : (
            <span />
          )}
          <span>{String(step + 1).padStart(2, "0")} / 03</span>
        </div>
      </div>
    </section>
  )
}
export function Onboarding() {
  const { step, setStep, go } = useApp()
  return (
    <Introduction
      step={step}
      setStep={setStep}
      onFinish={() => go("Authentication")}
    />
  )
}
