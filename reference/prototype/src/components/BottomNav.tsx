import { motion } from "motion/react"
import { useApp } from "../app-state"
import { useMotionPrefs } from "../motion"
import { Button } from "./Button"
import { Icon } from "./Icon"

const hiddenOn = [
  "Splash",
  "Conversation",
  "Onboarding",
  "Authentication",
  "Verification",
  "Enterprises",
]
const tabs = [
  ["chat", "Chats"],
  ["spark", "AI Agents"],
  ["file", "Submissions"],
  ["user", "Profile"],
] as const

export function BottomNav() {
  const { screen, go, setFilter } = useApp()
  const { layout } = useMotionPrefs()
  if (hiddenOn.includes(screen)) return null
  return (
    <nav>
      {tabs.map(([i, n]) => (
        <Button
          key={n}
          aria-current={screen === n ? "page" : undefined}
          className={screen === n ? "active" : ""}
          onClick={() => {
            go(n)
            setFilter("All")
          }}
        >
          <span>
            <Icon name={i} />
            {n === "Chats" && <b />}
          </span>
          {n}
          {screen === n && (
            <motion.i
              className="tab-indicator"
              layoutId="tab-indicator"
              transition={layout}
            />
          )}
        </Button>
      ))}
    </nav>
  )
}
