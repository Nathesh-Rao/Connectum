import { AnimatePresence } from "motion/react"
import { useApp } from "../app-state"
import { Avatar } from "../components/Avatar"
import { Button } from "../components/Button"
import { FilterChips } from "../components/FilterChips"
import { Icon } from "../components/Icon"
import { Landing, Rise, useSettled } from "../components/Landing"
import { conversations } from "../data/conversations"
import { useMotionPrefs } from "../motion"

export function Chats() {
  const {
    enterprise,
    filter,
    query,
    go,
    setSheet,
    setFilter,
    setQuery,
    openChat,
  } = useApp()
  const settled = useSettled()
  const { reduce } = useMotionPrefs()
  return (
    <Landing id="Chats" once>
      <Rise as="header" index={0}>
        <Button className="enterprise" onClick={() => setSheet("Enterprises")}>
          <span>
            <small>YOUR ENTERPRISE</small>
            <strong>
              {enterprise} <Icon name="chevron" />
            </strong>
          </span>
        </Button>
        <Button
          className="icon-button notification"
          aria-label="Notifications"
          onClick={() => go("Notifications")}
        >
          <Icon name="bell" />
          <b />
        </Button>
        <Button className="avatar-button" onClick={() => go("Profile")}>
          <Avatar name="Alex Morgan" photo />
        </Button>
      </Rise>
      <Rise className="search-row" index={1}>
        <div className="search">
          <Icon name="search" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search people, teams, messages"
          />
        </div>
        <Button
          className="new-chat-btn"
          aria-label="New chat"
          onClick={() => setSheet("New Group / Chat")}
        >
          <Icon name="compose" />
        </Button>
      </Rise>
      <FilterChips
        id="chats"
        landing={1}
        items={[{ label: "All", badge: "8" }, { label: "Direct & Teams" }]}
        value={filter}
        onChange={setFilter}
      />
      <div className="chat-scroll">
        <Button
          className="workspace"
          landing={2}
          onClick={() => openChat("My Work Space")}
        >
          <span className="workspace-icon">
            <Icon name="workspace" />
          </span>
          <span>
            <strong>
              My Work Space <span className="pinned">PINNED</span>
            </strong>
            <small>Commands, tasks & enterprise updates</small>
          </span>
          <Icon name="arrow" />
        </Button>
        <div className="section-label">Direct & Teams</div>
        <AnimatePresence mode="popLayout">
          {conversations
            .filter((x) => x.name.toLowerCase().includes(query.toLowerCase()))
            .map((x, i) => (
              <Button
                key={x.name}
                layout={!reduce}
                exit={{ opacity: 0 }}
                landing={settled.current ? "late" : 3 + i}
                className={`conversation ${x.count ? "unread" : ""}`}
                onClick={() => openChat(x.name)}
              >
                <Avatar
                  name={x.photo ? x.name : x.initial}
                  tone={x.tone}
                  photo={x.photo}
                />
                <span className="row-copy">
                  <strong>{x.name}</strong>
                  <small>{x.preview}</small>
                  <span className="conversation-type">
                    {x.initial === "DC"
                      ? "Group"
                      : x.initial === "PE"
                        ? "Team"
                        : "Direct message"}
                  </span>
                </span>
                <span className="row-meta">
                  <small>{x.time}</small>
                  {!!x.count && <b>{x.count}</b>}
                </span>
              </Button>
            ))}
        </AnimatePresence>
        {query &&
          ![
            "priya sharma",
            "design collective",
            "arjun mehta",
            "product & engineering",
          ].some((x) => x.includes(query.toLowerCase())) && (
            <p className="empty">No conversations found.</p>
          )}
      </div>
    </Landing>
  )
}
