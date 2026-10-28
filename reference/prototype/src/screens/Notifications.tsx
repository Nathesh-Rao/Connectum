import { useApp } from "../app-state"
import { Button } from "../components/Button"
import { Icon } from "../components/Icon"

export function Notifications() {
  const { go } = useApp()
  return (
    <>
      <div className="page-heading">
        <Button className="icon-button" onClick={() => go("Chats")}>
          <Icon name="back" />
        </Button>
        <h2>Notifications</h2>
      </div>
      <div className="page-content">
        <div className="section-label">TODAY</div>
        <Button
          className="notification-card"
          onClick={() => go("Submission detail")}
        >
          <Icon name="file" />
          <strong>New submission from Priya</strong>
          <p>chart_test · Ortho · ₹1,200</p>
          <small>12 minutes ago</small>
        </Button>
        <p className="quiet">You’re all caught up.</p>
      </div>
    </>
  )
}
