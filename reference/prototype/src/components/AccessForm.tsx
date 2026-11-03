import { useEffect, useRef, useState } from "react"
import { Ambient } from "./Ambient"
import { Button } from "./Button"
import { motion } from "motion/react"
import { Icon } from "./Icon"
import { Landing, Rise } from "./Landing"
import { distance, duration, ease, useMotionPrefs } from "../motion"

export function AccessForm({
  verification,
  email,
  setEmail,
  onContinue,
  onBack,
}: any) {
  const [mode, setMode] = useState("Sign In"),
    [error, setError] = useState(""),
    [digits, D] = useState(Array(6).fill("")),
    [busy, B] = useState(false),
    [seconds, C] = useState(9)
  const cells = useRef<(HTMLInputElement | null)[]>([])
  const { reduce } = useMotionPrefs()
  useEffect(() => {
    if (!verification) return
    const timer = setInterval(() => C((n) => Math.max(0, n - 1)), 1000)
    return () => clearInterval(timer)
  }, [verification])
  const submit = (e: any) => {
    e.preventDefault()
    if (verification ? digits.some((d) => !d) : !/^\S+@\S+\.\S+$/.test(email)) {
      setError(
        verification
          ? "Enter all six digits to continue."
          : "Enter a valid email address.",
      )
      return
    }
    setError("")
    B(true)
    setTimeout(() => {
      B(false)
      onContinue()
    }, 650)
  }
  return (
    <Landing id={verification ? "Verification" : "Authentication"}>
      <section
        className={"access " + (verification ? "verification-access" : "")}
      >
        <Rise className="access-branding" index={0}>
          <Ambient />
          <div className="access-top">
            {verification ? (
              <Button
                className="icon-button"
                aria-label="Back to email"
                onClick={onBack}
              >
                <Icon name="back" />
              </Button>
            ) : (
              <span />
            )}
            <span className="secure-label">
              {verification ? "02 / VERIFY" : "01 / YOUR ACCOUNT"}
            </span>
          </div>
          <div className="access-heading">
            <img
              className="access-logo"
              src="/connectum-logo.png"
              alt="Connectum logo"
            />
            <h2>{verification ? "Check your inbox" : "Connectum"}</h2>
            <p>
              {verification ? (
                <>
                  We sent a 6-digit code to
                  <br />
                  <strong>{email || "alex@agilelabs.com"}</strong>
                </>
              ) : (
                "One account for every enterprise you work with."
              )}
            </p>
          </div>
        </Rise>
        <Rise as="form" index={1} onSubmit={submit} className="access-form">
          {!verification && (
            <div className="mode-selector">
              {["Sign In", "Set Up", "Self Register"].map((x) => (
                <Button
                  key={x}
                  type="button"
                  className={x === mode ? "chosen" : ""}
                  onClick={() => {
                    setMode(x)
                    setError("")
                  }}
                >
                  {x}
                </Button>
              ))}
            </div>
          )}
          {verification ? (
            <>
              <label>Verification code</label>
              <div className={"otp-cells " + (error ? "has-error" : "")}>
                {digits.map((d, i) => (
                  <motion.span
                    key={i}
                    className="otp-cell"
                    initial={
                      reduce
                        ? false
                        : { opacity: 0, scale: 0.85, y: distance.rise / 2 }
                    }
                    animate={{ opacity: 1, scale: 1, y: 0 }}
                    transition={{
                      delay: 0.12 + i * 0.04,
                      duration: duration.base,
                      ease: ease.out,
                    }}
                  >
                    <input
                      ref={(el) => {
                        cells.current[i] = el
                      }}
                      aria-label={`Digit ${i + 1}`}
                      inputMode="numeric"
                      autoComplete={i === 0 ? "one-time-code" : "off"}
                      value={d}
                      maxLength={1}
                      onChange={(e) => {
                        const v = e.target.value.replace(/\D/g, "").slice(-1)
                        D((a) => a.map((x, j) => (i === j ? v : x)))
                        setError("")
                        if (v) cells.current[i + 1]?.focus()
                      }}
                      onKeyDown={(e) => {
                        if (e.key === "Backspace" && !d)
                          cells.current[i - 1]?.focus()
                      }}
                      onPaste={(e) => {
                        e.preventDefault()
                        const v = e.clipboardData
                          .getData("text")
                          .replace(/\D/g, "")
                          .slice(0, 6)
                        D(Array.from({ length: 6 }, (_, j) => v[j] || ""))
                        cells.current[Math.min(v.length, 5)]?.focus()
                        setError("")
                      }}
                    />
                  </motion.span>
                ))}
              </div>
            </>
          ) : (
            <>
              <p className="mode-description">
                {mode === "Sign In"
                  ? "A secure code. No password to remember."
                  : mode === "Set Up"
                    ? "Set up your enterprise with your email."
                    : "Register your personal Connectum account."}
              </p>
              <label htmlFor="access-email">Email address</label>
              <div className={"email-input " + (error ? "has-error" : "")}>
                <span>@</span>
                <input
                  id="access-email"
                  type="email"
                  value={email}
                  onChange={(e) => {
                    setEmail(e.target.value)
                    setError("")
                  }}
                  placeholder="you@enterprise.com"
                  autoComplete="email"
                  required
                />
              </div>
            </>
          )}
          {error && (
            <p className="field-error" role="alert">
              {error}
            </p>
          )}
          <Button className="primary" disabled={busy} type="submit">
            {busy
              ? verification
                ? "Verifying…"
                : "Sending code…"
              : verification
                ? "Verify & continue"
                : mode === "Sign In"
                  ? "Sign in"
                  : mode === "Set Up"
                    ? "Continue with Set Up"
                    : "Self Register"}
            {!busy && <Icon name="arrow" />}
          </Button>
          {verification ? (
            <div className="code-actions">
              <Button type="button" onClick={onBack}>
                Change email
              </Button>
              <Button type="button" disabled={seconds > 0} onClick={() => C(9)}>
                {seconds ? `Send again in ${seconds}s` : "Send again"}
              </Button>
            </div>
          ) : (
            <p className="access-help">
              We’ll email you a one-time verification code.
            </p>
          )}
        </Rise>
        <Rise className="access-footer" index={2}>
          <Icon name="check" />
          <span>Private by design. Connected by choice.</span>
        </Rise>
      </section>
    </Landing>
  )
}
