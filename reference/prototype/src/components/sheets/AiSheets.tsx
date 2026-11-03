import { useState } from "react"
import { useApp } from "../../app-state"
import { Button } from "../Button"
import { Icon } from "../Icon"
import { Landing } from "../Landing"

export function AiHistory() {
  const { ai, setSheet } = useApp()
  const [query, setQuery] = useState("")
  const list = ai.chats.filter((c) =>
    c.title.toLowerCase().includes(query.trim().toLowerCase()),
  )
  return (
    <Landing id="ai-history">
      <div className="forms-search">
        <Icon name="search" />
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search past chats"
        />
      </div>
      <div className="forms-list">
        {list.map((c, i) => (
          <Button
            key={c.id}
            className="setting history-row"
            landing={1 + i}
            onClick={() => {
              ai.openChat(c.id)
              setSheet("")
            }}
          >
            <span className="history-copy">
              <strong>{c.title}</strong>
              <small>{c.updated}</small>
            </span>
            {ai.activeId === c.id ? (
              <Icon name="check" />
            ) : (
              <Icon name="arrow" />
            )}
          </Button>
        ))}
        {!list.length && <p className="empty">No chats found.</p>}
      </div>
    </Landing>
  )
}

const models = [
  ["Auto", "Picks the best mode for each question"],
  ["Fast", "Quick answers for everyday questions"],
  ["Thinking", "Takes longer on harder questions"],
] as const

export function AiModel() {
  const { ai, setSheet } = useApp()
  return (
    <Landing id="ai-model">
      {models.map(([name, hint], i) => (
        <Button
          key={name}
          className="setting history-row"
          landing={i}
          onClick={() => {
            ai.setModel(name)
            setSheet("")
          }}
        >
          <span className="history-copy">
            <strong>{name}</strong>
            <small>{hint}</small>
          </span>
          {ai.model === name && <Icon name="check" />}
        </Button>
      ))}
    </Landing>
  )
}

export function AiAgents() {
  const { setSheet } = useApp()
  return (
    <Landing id="ai-agents">
      <Button
        className="setting history-row"
        landing={0}
        onClick={() => setSheet("")}
      >
        <span className="history-copy">
          <strong>openai</strong>
          <small>Your workspace assistant</small>
        </span>
        <Icon name="check" />
      </Button>
      <p className="muted">
        More agents will appear here when your admin adds them.
      </p>
    </Landing>
  )
}
