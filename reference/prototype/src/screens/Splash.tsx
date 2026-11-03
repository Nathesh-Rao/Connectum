import { useEffect } from "react"
import { useIsPresent } from "motion/react"
import { useApp } from "../app-state"
import { Ambient } from "../components/Ambient"

export function Splash() {
  const { go, setStep } = useApp()
  // Stays mounted while it animates out, so stop the timer as soon as the
  // screen is no longer present.
  const present = useIsPresent()
  useEffect(() => {
    if (!present) return
    const timer = setTimeout(() => {
      setStep(0)
      go("Onboarding")
    }, 1800)
    return () => clearTimeout(timer)
  }, [go, setStep, present])
  return (
    <div className="splash">
      <Ambient />
      <img src="/connectum-logo.png" alt="Connectum" />
    </div>
  )
}
