import { useApp } from "../app-state"
import { cardFields, statusOf } from "../data/submissions"
import { Button } from "./Button"
import { FilterChips } from "./FilterChips"
import { Icon } from "./Icon"
import { Landing, Rise } from "./Landing"
import { YesNo } from "./YesNo"

export function SubmissionsLayout({ detail }: { detail: boolean }) {
  const {
    filter,
    submissions,
    selected,
    go,
    setFilter,
    selectSubmission,
    openEdit,
  } = useApp()
  const list = detail
    ? submissions.filter((s) => s.id === selected)
    : submissions.filter(
        (s) =>
          s.direction === "sent" &&
          (filter === "All" || statusOf(s) === filter),
      )
  return (
    <Landing id={detail ? "Submission detail" : "Submissions"} once={!detail}>
      <Rise className="page-heading" index={0}>
        <Button
          className="icon-button"
          onClick={() => go(detail ? "Conversation" : "Chats")}
        >
          <Icon name="back" />
        </Button>
        <h2>{!detail ? "My Submissions" : "Submission detail"}</h2>
      </Rise>
      <div className="page-content">
        <FilterChips
          id={detail ? "detail" : "submissions"}
          landing={1}
          items={[{ label: "All" }, { label: "Pending" }, { label: "Paid" }]}
          value={filter}
          onChange={setFilter}
        />
        {list.map((s, i) => {
          const status = statusOf(s)
          // The list shows the first few values; the detail shows them all.
          const rows = cardFields(s, 120)
          const shown = detail ? rows : rows.slice(0, 4)
          return (
            <Button
              key={s.id}
              className="detail-card"
              landing={2 + i}
              onClick={() => {
                selectSubmission(s.id)
                if (!detail) go("Submission detail")
                else if (s.direction === "sent") openEdit(s.id)
              }}
            >
              <span className={"paid " + status.toLowerCase()}>{status}</span>
              <h2>{s.title}</h2>
              <p>
                Submission #{s.id} · {s.form}
              </p>
              {shown.map((f) => (
                <div className="kv" key={f.key}>
                  <span>{f.label}</span>
                  {f.type === "yesno" ? (
                    <YesNo value={f.text} />
                  ) : (
                    <strong>{f.text}</strong>
                  )}
                </div>
              ))}
              {detail && (
                <div className="kv">
                  <span>
                    {s.direction === "sent" ? "Submitted by" : "Shared by"}
                  </span>
                  <strong>{s.sender}</strong>
                </div>
              )}
              {detail && s.direction === "received" ? (
                <span className="read-only">
                  Read-only · shared by {s.sender}
                </span>
              ) : (
                <span className="text-link">
                  {!detail ? "View details →" : "Edit submission →"}
                </span>
              )}
            </Button>
          )
        })}
        {!list.length && <p className="empty">No submissions here.</p>}
      </div>
    </Landing>
  )
}
