import { useApp, type Screen } from "../app-state"
import { Button } from "./Button"
import { Icon } from "./Icon"

export function StudioSidebar() {
  const { screen, go } = useApp()
  return (
    <aside className="direction">
      <div className="brand">
        <img src="/connectum-logo.png" alt="Connectum" />
        Connectum
      </div>
      <div className="direction-copy">
        <span className="section-kicker">THE CONNECTUM EXPERIENCE</span>
        <h1>
          Everything connected.
          <br />
          Nothing in the way.
        </h1>
        <p>
          A quieter place for conversations,
          <br />
          enterprises and the work between them.
        </p>
      </div>
      <div className="screen-index">
        {[
          ["Splash", "00", "Splash & onboarding"],
          ["Authentication", "01", "Sign In"],
          ["Verification", "02", "Verification"],
          ["Enterprises", "03", "Enterprises"],
          ["Chats", "04", "Conversations"],
        ].map(([key, n, title]) => (
          <Button
            key={key}
            className={screen === key ? "current" : ""}
            onClick={() => go(key as Screen)}
          >
            <span>{n}</span>
            {title}
            <Icon name="arrow" />
          </Button>
        ))}
      </div>
      <small className="direction-note">
        WARM SIGNAL / MOBILE PRODUCT STUDY
      </small>
    </aside>
  )
}
