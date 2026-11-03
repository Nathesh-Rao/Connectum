import { useApp } from "../../app-state"
import { Button } from "../Button"
import { Icon } from "../Icon"

export function AiHeader() {
  const { ai, setSheet } = useApp()
  return (
    <header className="ai-header">
      <Button className="agent-pill" onClick={() => setSheet("AI agents")}>
        <span className="agent-dot-icon">
          <Icon name="spark" />
        </span>
        openai
        <Icon name="chevron" />
      </Button>
      <Button
        className="icon-button"
        aria-label="History"
        onClick={() => setSheet("AI history")}
      >
        <Icon name="clock" />
      </Button>
      <Button
        className="icon-button"
        aria-label="New chat"
        onClick={() => ai.newChat()}
      >
        <Icon name="compose" />
      </Button>
    </header>
  )
}
