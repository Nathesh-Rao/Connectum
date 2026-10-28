import { AnimatePresence, motion, useIsPresent } from "motion/react"
import { useApp } from "../app-state"
import { duration, useMotionPrefs } from "../motion"
import { Button } from "./Button"
import { EnterpriseAvatar } from "./EnterpriseAvatar"
import { Icon } from "./Icon"
import { AiAgents, AiHistory, AiModel } from "./sheets/AiSheets"
import { FormsPicker } from "./sheets/FormsPicker"
import { codes, enterprises } from "../data/enterprises"

// Springs up from the bottom over a fading backdrop and animates out on close.
// The panel keeps the name it opened with so its content survives the exit.
export function Sheet() {
  const { sheet } = useApp()
  return (
    <AnimatePresence>
      {sheet && <SheetPanel key="sheet" name={sheet} />}
    </AnimatePresence>
  )
}

// Sheets with long lists get a fixed height and scroll inside.
const tall = ["Forms", "AI history"]
const titles: Record<string, string> = {
  "AI history": "History",
  "AI model": "Model",
  "AI agents": "Agent",
}

function SheetPanel({ name: sheet }: { name: string }) {
  const { reduce, spring, tween } = useMotionPrefs()
  const present = useIsPresent()
  const { enterprise, person, go, setSheet, setEnterprise, setText, openChat } =
    useApp()
  return (
    <motion.div
      className="overlay"
      style={{ pointerEvents: present ? undefined : "none" }}
      onClick={() => setSheet("")}
      initial="hidden"
      animate="shown"
      exit="hidden"
    >
      <motion.div
        className="sheet-backdrop"
        variants={{ hidden: { opacity: 0 }, shown: { opacity: 1 } }}
        transition={tween(duration.base)}
      />
      <motion.section
        className={"sheet" + (tall.includes(sheet) ? " tall" : "")}
        onClick={(e) => e.stopPropagation()}
        variants={{
          hidden: {
            ...(reduce ? { opacity: 0 } : { y: "100%" }),
            transition: tween(duration.base),
          },
          shown: { opacity: 1, y: 0, transition: spring },
        }}
      >
        <div className="handle" />
        <div className="sheet-title">
          <h2>{titles[sheet] ?? sheet}</h2>
          <Button onClick={() => setSheet("")} aria-label="Close">
            ×
          </Button>
        </div>
        <motion.div
          key={sheet}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={tween(duration.fast)}
        >
          {sheet === "Account options" ? (
            <>
              {["Set a password", "Sign out"].map((x) => (
                <Button key={x} className="setting" onClick={() => setSheet(x)}>
                  {x}
                  <Icon name="arrow" />
                </Button>
              ))}
            </>
          ) : sheet === "Enterprises" ? (
            <>
              <p className="muted">One account. Every enterprise.</p>
              {enterprises.map((e, i) => (
                <Button
                  key={e}
                  className="enterprise-row"
                  onClick={() => {
                    setEnterprise(e)
                    go("Chats")
                    setSheet("")
                  }}
                >
                  <EnterpriseAvatar index={i} />
                  <span>
                    <strong>{e}</strong>
                    <small>Member · {codes[i]}</small>
                  </span>
                  <Icon name={enterprise === e ? "check" : "arrow"} />
                </Button>
              ))}
              <Button
                className="primary"
                onClick={() => setSheet("Join another enterprise")}
              >
                <Icon name="plus" /> Join another enterprise
              </Button>
            </>
          ) : sheet === "Join another enterprise" ? (
            <>
              <p>Enter the enterprise code shared by your admin.</p>
              <input placeholder="Enterprise code · CMYD-Z063" />
              <Button
                className="primary"
                onClick={() => setSheet("Join Agile Labs")}
              >
                Continue <Icon name="arrow" />
              </Button>
              <p className="muted">
                Camera scanning is not connected in this prototype.
              </p>
            </>
          ) : sheet === "Join Agile Labs" ? (
            <>
              <p>
                Join Agile Labs to connect with your team and access shared
                workflows.
              </p>
              <Button
                className="primary"
                onClick={() => {
                  setEnterprise("Agile Labs")
                  go("Chats")
                  setSheet("")
                }}
              >
                Join enterprise
              </Button>
            </>
          ) : sheet === "New Group / Chat" ? (
            <>
              {[
                "Priya Sharma",
                "Arjun Mehta",
                "Design Collective",
                "openai",
              ].map((n) => (
                <Button
                  key={n}
                  className="setting"
                  onClick={() => {
                    openChat(n)
                    setSheet("")
                  }}
                >
                  {n}
                  <Icon name="arrow" />
                </Button>
              ))}
            </>
          ) : sheet === "Commands" ? (
            <>
              {[
                "# leave — Request time off",
                "# approval — Start an approval",
                "# update — Share a team update",
              ].map((n) => (
                <Button
                  key={n}
                  className="setting"
                  onClick={() => {
                    setText(n.split(" —")[0])
                    setSheet("")
                  }}
                >
                  {n}
                </Button>
              ))}
              <small className="muted">
                Sample commands · admin-configured options
              </small>
            </>
          ) : sheet === "Forms" ? (
            <FormsPicker />
          ) : sheet === "AI history" ? (
            <AiHistory />
          ) : sheet === "AI model" ? (
            <AiModel />
          ) : sheet === "AI agents" ? (
            <AiAgents />
          ) : sheet === "Conversation tools" ? (
            <>
              {[
                "My Submissions",
                "Tool 1 — feature to be confirmed",
                "Tool 2 — feature to be confirmed",
              ].map((n) => (
                <Button
                  key={n}
                  className="setting"
                  onClick={() =>
                    n === "My Submissions"
                      ? (go("Submissions"), setSheet(""))
                      : setSheet(n)
                  }
                >
                  {n}
                  <Icon name="arrow" />
                </Button>
              ))}
            </>
          ) : sheet === "Attachments" ? (
            <>
              {["Camera", "Photo", "File"].map((x) => (
                <Button
                  key={x}
                  className="setting"
                  onClick={() => setSheet(`${x} picker — not connected`)}
                >
                  {x}
                  <Icon name="plus" />
                </Button>
              ))}
            </>
          ) : sheet === "Sign out" ? (
            <>
              <p>Sign out of Connectum on this device?</p>
              <Button
                className="primary"
                onClick={() => {
                  go("Authentication")
                  setSheet("")
                }}
              >
                Sign out
              </Button>
            </>
          ) : sheet === "Conversation details" ? (
            <>
              <p>{person} · Agile Labs</p>
              {["Members", "Shared files", "Mute conversation"].map((x) => (
                <Button key={x} className="setting" onClick={() => setSheet(x)}>
                  {x}
                  <Icon name="arrow" />
                </Button>
              ))}
            </>
          ) : (
            <>
              <p className="muted">
                {sheet === "Saved successfully"
                  ? "Your submission changes have been saved for this preview."
                  : "This feature is a prototype preview and is not connected to a service."}
              </p>
              <Button className="primary" onClick={() => setSheet("")}>
                Got it
              </Button>
            </>
          )}
        </motion.div>
      </motion.section>
    </motion.div>
  )
}
