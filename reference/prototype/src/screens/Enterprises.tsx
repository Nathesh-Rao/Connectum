import { useApp } from "../app-state"
import { Button } from "../components/Button"
import { EnterpriseAvatar } from "../components/EnterpriseAvatar"
import { Icon } from "../components/Icon"
import { useState } from "react"
import { Landing, Rise } from "../components/Landing"
import { duration, ease, useMotionPrefs } from "../motion"
import { codes, enterprises } from "../data/enterprises"

export function Enterprises() {
  const { enterprise, go, setSheet, setEnterprise } = useApp()
  const { reduce } = useMotionPrefs()
  // The chosen card scales up and fades while the screen hands over to Chats.
  const [chosen, setChosen] = useState<string | null>(null)
  return (
    <Landing id="Enterprises">
      <section className="enterprise-page">
        <Rise className="enterprise-page-top" index={0}>
          <span className="access-wordmark">
            <img src="/connectum-logo.png" alt="" />
            Connectum
          </span>
          <Button
            className="icon-button"
            aria-label="Account options"
            onClick={() => setSheet("Account options")}
          >
            <Icon name="more" />
          </Button>
        </Rise>
        <Rise className="enterprise-heading" index={1}>
          <span className="section-kicker">YOUR CONNECTED WORLD</span>
          <h2>
            Choose an
            <br />
            enterprise.
          </h2>
          <p>Pick where you’d like to work today.</p>
        </Rise>
        <Button
          className="identity-strip"
          landing={1}
          onClick={() => {
            navigator.clipboard?.writeText("MN68-2CQ9")
            setSheet("Connectum ID copied")
          }}
        >
          <span>Connectum ID</span>
          <strong>MN68-2CQ9</strong>
          <Icon name="file" />
        </Button>
        <div className="enterprise-list">
          {enterprises.map((e, i) => (
            <Button
              key={e}
              landing={2 + i}
              {...(chosen === e && !reduce
                ? {
                    animate: {
                      scale: 1.06,
                      opacity: 0,
                      transition: { duration: duration.base, ease: ease.out },
                    },
                  }
                : {})}
              className={
                "enterprise-choice " + (enterprise === e ? "is-current" : "")
              }
              onClick={() => {
                setChosen(e)
                setEnterprise(e)
                go("Chats")
              }}
            >
              <EnterpriseAvatar index={i} />
              <span className="enterprise-copy">
                <strong>{e}</strong>
                <small>Member · {codes[i]}</small>
              </span>
              {enterprise === e ? (
                <span className="current-check">
                  <Icon name="check" />
                </span>
              ) : (
                <Icon name="arrow" />
              )}
            </Button>
          ))}
        </div>
        <Button
          className="join-row"
          landing={7}
          onClick={() => setSheet("Join another enterprise")}
        >
          <Icon name="plus" />
          Join another enterprise
          <Icon name="arrow" />
        </Button>
        <div className="enterprise-bottom">
          <Button onClick={() => setSheet("Refreshed")}>Refresh</Button>
          <span>One account. Every enterprise.</span>
        </div>
      </section>
    </Landing>
  )
}
