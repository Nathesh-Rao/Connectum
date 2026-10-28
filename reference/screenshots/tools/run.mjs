import puppeteer from "puppeteer-core"
import fs from "node:fs"
import path from "node:path"

const ROOT = "/Users/narasimhanatheshrao/Development/prototype/reference-screenshots"
const SPECS = path.join(ROOT, "specs")
fs.mkdirSync(SPECS, { recursive: true })
const extractSrc = fs.readFileSync(new URL("./extract.js", import.meta.url), "utf8").replace("export function", "function")
const only = process.argv[2] // optional: stop after N captures for debugging

const browser = await puppeteer.launch({
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: true,
  args: ["--no-sandbox", "--hide-scrollbars"],
})
const page = await browser.newPage()
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 })
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const log = []
let n = 0
const missing = []

async function phone() { return page.$(".phone") }

async function clickText(text, { within = ".phone", tag = "button", nth = 0, exact = true } = {}) {
  const h = await page.evaluateHandle(({ text, within, tag, nth, exact }) => {
    const root = document.querySelector(within) || document
    const els = [...root.querySelectorAll(tag)].filter((e) => {
      const r = e.getBoundingClientRect()
      const t = (e.getAttribute("aria-label") || e.textContent || "").replace(/\s+/g, " ").trim()
      return r.width > 0 && r.height > 0 && (exact ? t === text : t.includes(text))
    })
    return els[nth] || null
  }, { text, within, tag, nth, exact })
  const el = h.asElement()
  if (!el) { missing.push(`click target not found: "${text}"`); throw new Error("not found: " + text) }
  await el.click()
}
async function clickSel(sel) { const el = await page.$(sel); if (!el) throw new Error("no " + sel); await el.click() }

async function shot(file, desc, src, { spec = null, settle = 0, fast = false } = {}) {
  if (settle) await sleep(settle)
  let A0 = null
  if (spec && fast) { A0 = await page.evaluate(`(${extractSrc})()`); await sleep(350) }
  await page.evaluate(() => getSelection()?.removeAllRanges())
  n++
  const name = `${String(n).padStart(2, "0")}-${file}.png`
  const el = await phone()
  await el.screenshot({ path: path.join(ROOT, name) })
  log.push([name, desc, src])
  if (spec) {
    const A = A0 ?? await page.evaluate(`(${extractSrc})()`)
    if (!fast) await sleep(700)
    const B = await page.evaluate(`(${extractSrc})()`)
    const bmap = new Map(B.elements.map((e) => [e.key, e]))
    let animated = 0
    for (const e of A.elements) {
      const o = bmap.get(e.key)
      const changed = o && (Math.abs(o.x - e.x) > 0.05 || Math.abs(o.y - e.y) > 0.05 || Math.abs(o.width - e.width) > 0.05 || Math.abs(o.height - e.height) > 0.05 || (o.style.transform ?? "") !== (e.style.transform ?? "") || (o.style.opacity ?? "") !== (e.style.opacity ?? "") || (o.style.effectiveOpacity ?? "") !== (e.style.effectiveOpacity ?? ""))
      e.animated = !!(changed || e.style.cssAnimation)
      if (changed) e.animatedSample = { atT0: { x: e.x, y: e.y, width: e.width, height: e.height, transform: e.style.transform, opacity: e.style.effectiveOpacity }, atT1: { x: o.x, y: o.y, width: o.width, height: o.height, transform: o.style.transform, opacity: o.style.effectiveOpacity } }
      if (e.animated) animated++
      delete e.key
    }
    const spec = {
      screen: file.replace(/^\d+-/, ""), screenshot: name, source: src,
      viewport: { width: 390, height: 844, deviceScaleFactor: 2 }, coordinateSpace: "CSS px relative to the .phone frame top-left",
      ...A, animatedElementCount: animated,
      animatedNote: "animated=true means rect/transform/opacity differed between two samples (~0.35-0.7s apart) or a CSS animation is set; see animatedSample for the two values.",
      backdrop: A.elements.filter((e) => /ambient|sphere|orbit|disc|onb-backdrop/.test(e.classes + e.label) && !/^svg (circle|path|rect|ellipse|line)/.test(e.label)).map((e) => ({ label: e.label, classes: e.classes, x: e.x, y: e.y, width: e.width, height: e.height, background: e.style.background, border: e.style.border, borderRadius: e.style.borderRadius, boxShadow: e.style.boxShadow, effectiveOpacity: e.style.effectiveOpacity ?? e.style.opacity, animated: e.animated, cssAnimation: e.style.cssAnimation })),
      ...(file.startsWith("onboarding") ? { onboardingSphereMotion: { source: "src/components/onboarding/OnboardingBackdrop.tsx", note: "each .onb-sphere loops (framer-motion, easeInOut, repeat Infinity): x [0,dx,-dx/2,0], y [0,dy,-dy/2,0], scale [1,1.1,0.94,1]; the group also parallax-shifts x by -60px per slide step", spheres: [{ left: "62%", top: 18, size: 58, dx: 14, dy: -10, durationS: 11, delayS: 0 }, { left: "14%", top: 214, size: 30, dx: -10, dy: -14, durationS: 9, delayS: 1.5 }, { left: "40%", top: 30, size: 22, dx: 12, dy: 12, durationS: 13, delayS: 3 }, { left: "78%", top: 238, size: 16, dx: -8, dy: -10, durationS: 8, delayS: 4.5 }] } } : {}),
      elements: A.elements,
    }
    fs.writeFileSync(path.join(SPECS, `${name.replace(".png", "")}.json`), JSON.stringify(spec, null, 1))
  }
  console.log("captured", name)
  if (only && n >= +only) { await browser.close(); process.exit(0) }
}
// spec-recording flag helper
const S = { spec: true }

// The splash auto-advances after 1.8s, which races the screenshot. In this browser session only
// (no source change) hold that one timer while capturing the splash, then reload and run it normally.
await page.evaluateOnNewDocument(() => {
  const st = window.setTimeout.bind(window)
  window.setTimeout = (f, d, ...a) => st(f, d === 1800 && location.hash === "#hold" ? 1e9 : d, ...a)
})
await page.goto("http://localhost:8443/#hold", { waitUntil: "networkidle0" })
await page.evaluate(() => document.fonts.ready)

// ---- Splash (logo-reveal 0.65s; auto-advances at 1.8s)
await shot("splash", "Splash: white screen, centred logo, faint ambient disc/orbit", "src/screens/Splash.tsx, src/components/Ambient.tsx, .splash in src/index.css", { ...S, settle: 1200 })
await page.goto("about:blank")
await page.goto("http://localhost:8443/", { waitUntil: "domcontentloaded" })

// ---- Onboarding
await page.waitForSelector(".introduction")
await shot("onboarding-1-conversations", "Onboarding slide 1: constellation art, 'All your conversations in one place'", "src/screens/Onboarding.tsx, src/components/onboarding/ConstellationArt.tsx", { ...S, settle: 3200 })
await clickText("Continue")
await shot("onboarding-2-enterprises", "Onboarding slide 2: enterprises art, 'Work across multiple enterprises'", "src/screens/Onboarding.tsx, src/components/onboarding/EnterprisesArt.tsx", { ...S, settle: 3200 })
await clickText("Continue")
await shot("onboarding-3-security", "Onboarding slide 3: security art, 'Secure, simple and ready to go'", "src/screens/Onboarding.tsx, src/components/onboarding/SecurityArt.tsx", { ...S, settle: 3200 })
await clickText("Get Started")

// ---- Authentication
await page.waitForSelector(".access")
await shot("auth-sign-in", "Authentication, Sign In mode (default)", "src/screens/Authentication.tsx, src/components/AccessForm.tsx", { ...S, settle: 1500 })
await clickText("Set Up", { within: ".mode-selector" })
await shot("auth-set-up", "Authentication, Set Up mode", "src/components/AccessForm.tsx", { ...S, settle: 500 })
await clickText("Self Register", { within: ".mode-selector" })
await shot("auth-self-register", "Authentication, Self Register mode", "src/components/AccessForm.tsx", { ...S, settle: 500 })
await clickText("Sign In", { within: ".mode-selector" })
await page.type("#access-email", "alex@example.com")
await clickText("Sign in", { exact: false })

// ---- Verification
await page.waitForSelector(".otp-cells")
await shot("verification-empty", "Verification, six empty code cells ('Send again in 8s' captured ~1.5s after mount)", "src/screens/Verification.tsx, src/components/AccessForm.tsx", { ...S, settle: 1400 })
await clickSel(".otp-cell input")
await page.keyboard.type("482916")
await page.mouse.click(5, 400) // blur so no focus ring is part of the capture
await shot("verification-filled", "Verification, all six digits entered", "src/components/AccessForm.tsx", { settle: 400 })
await clickText("Verify", { exact: false })

// ---- Enterprises
await page.waitForSelector(".enterprise-page")
await shot("enterprises", "Enterprises list (current: Agile Labs not yet chosen), Connectum ID strip, join row", "src/screens/Enterprises.tsx", { ...S, settle: 1800 })
await clickText("Join another enterprise", { exact: false })
await shot("enterprises-join-step1", "Join sheet, step 1: enterprise code input", "src/components/Sheet.tsx ('Join another enterprise')", { ...S, settle: 900 })
await clickText("Continue", { within: ".sheet" })
await shot("enterprises-join-step2", "Join sheet, step 2: confirm joining Agile Labs", "src/components/Sheet.tsx ('Join Agile Labs')", { ...S, settle: 900 })
await clickSel('.sheet [aria-label="Close"]'); await sleep(600)
await clickSel('[aria-label="Account options"]')
await shot("enterprises-account-sheet", "Account options sheet: Set a password / Sign out", "src/components/Sheet.tsx ('Account options')", { ...S, settle: 900 })
await clickSel('.sheet [aria-label="Close"]'); await sleep(600)

// ---- Chats
await clickText("Agile Labs", { within: ".enterprise-list", tag: "button", exact: false })
await page.waitForSelector(".chat-scroll")
await shot("chats-home", "Chats home: enterprise header, search, filters, pinned workspace, conversation list, bottom nav", "src/screens/Chats.tsx, src/components/BottomNav.tsx", { settle: 1800 })
await clickSel('[aria-label="New chat"]')
await shot("chats-new-chat-sheet", "New Group / Chat sheet", "src/components/Sheet.tsx ('New Group / Chat')", { settle: 900 })
await clickSel('.sheet [aria-label="Close"]'); await sleep(600)
await clickSel(".enterprise")
await shot("chats-enterprise-switcher-sheet", "Enterprise switcher sheet", "src/components/Sheet.tsx ('Enterprises')", { settle: 900 })
await clickSel('.sheet [aria-label="Close"]'); await sleep(600)
await clickSel('[aria-label="Notifications"]')
await shot("notifications", "Notifications screen", "src/screens/Notifications.tsx", { settle: 1000 })
await clickSel(".page-heading .icon-button"); await sleep(900)

// ---- Conversation
await clickText("Priya Sharma", { within: ".chat-scroll", exact: false })
await page.waitForSelector(".conv")
await sleep(1500)
await page.evaluate(() => { const t = document.querySelector(".thread"); if (t) t.scrollTop = t.scrollHeight })
await shot("conversation-bottom", "Conversation with Priya Sharma, scrolled to the bottom (latest messages)", "src/screens/Conversation.tsx, src/components/conversation/ThreadView.tsx", { settle: 600 })

await page.evaluate(() => document.querySelector(".sub-card.sent")?.scrollIntoView({ block: "center" }))
await shot("conversation-sent-form-card", "Conversation: a SENT form card (#1040, mine, has edit pencil in the dark strip), plus message bubbles", "src/components/FormCard.tsx (.sub-card.sent), src/components/conversation/ThreadView.tsx", { settle: 700 })
await page.evaluate(() => { const t = document.querySelector(".thread"); t.scrollTop = t.scrollHeight })
await shot("conversation-received-form-card", "Conversation: a RECEIVED form card (#1042, read-only, no edit pencil) with incoming bubble and 'typing' row", "src/components/FormCard.tsx (.sub-card.received)", { settle: 700 })

// forms picker -> form screen
await clickSel('[aria-label="Forms"]')
await shot("forms-picker-sheet", "Forms picker sheet: search, Recent chips, All forms list, My Submissions", "src/components/sheets/FormsPicker.tsx", { settle: 1200 })
await clickText("Clinical examination - Ortho", { within: ".sheet", exact: false, nth: 0 })
await page.waitForSelector(".form-screen")
await shot("form-screen-empty", "Form screen (Clinical examination - Ortho), untouched, defaults only", "src/components/FormScreen.tsx", { settle: 1500 })
await clickText("Done", { within: ".form-screen" })
await shot("form-screen-errors", "Same form after tapping Done with required fields empty: red 'This field is required' errors", "src/components/FormScreen.tsx", { settle: 700 })
await clickSel('.form-screen [aria-label="Cancel"]'); await sleep(900)

// commands sheet
await clickSel(".composer input")
await page.keyboard.type("#")
await shot("commands-sheet", "Commands sheet opened by typing '#' in the composer", "src/components/Sheet.tsx ('Commands'), src/screens/Conversation.tsx", { settle: 900 })
await clickSel('.sheet [aria-label="Close"]'); await sleep(700)
await page.click(".composer input", { clickCount: 3 }); await page.keyboard.press("Backspace"); await sleep(200)
await page.mouse.click(5, 600)

// summarise panel
await clickSel('[aria-label="Summarise this chat"]')
await shot("summarise-60", "Summarise panel at its resting 60% height: chips, scope hint, ask input", "src/components/conversation/SummaryPanel.tsx", { settle: 1500 })
const grip = await (await page.$(".sum-grip")).boundingBox()
await page.mouse.move(grip.x + grip.width / 2, grip.y + 12)
await page.mouse.down()
for (let i = 1; i <= 14; i++) { await page.mouse.move(grip.x + grip.width / 2, grip.y + 12 - i * 30); await sleep(16) }
await page.mouse.up()
await shot("summarise-full", "Summarise panel dragged to full (94%) height", "src/components/conversation/SummaryPanel.tsx", { settle: 1200 })
await clickSel('.sum-panel [aria-label="Close"]'); await sleep(900)
await clickSel(".thread-header .icon-button"); await sleep(1200) // back to chats

// AI tab
await clickText("AI Agents", { within: "nav" })
await shot("ai-agents-empty", "AI Agents tab, empty state with suggestions", "src/screens/AiAgents.tsx, src/components/ai/AiEmpty.tsx, AiHeader.tsx, AiComposer.tsx", { settle: 1500 })
await clickSel(".ai-empty button, .ai-suggest button, .ai-suggestions button")
await shot("ai-agents-conversation", "AI Agents tab mid-conversation (question sent, answer streaming/just arrived)", "src/components/ai/AiThread.tsx", { settle: 1600 })

// Submissions
await clickText("Submissions", { within: "nav" })
await shot("submissions-list", "My Submissions list with filter chips and cards", "src/screens/Submissions.tsx, src/components/SubmissionsLayout.tsx", { settle: 1500 })
await clickSel(".detail-card"); await page.waitForSelector(".page-heading")
await shot("submission-detail", "Submission detail", "src/screens/SubmissionDetail.tsx, src/components/SubmissionsLayout.tsx", { settle: 1500 })
await clickSel(".page-heading .icon-button"); await sleep(900)
// from detail the back goes to Conversation; use the tab bar? Detail has the nav -> Profile
await clickSel(".thread-header .icon-button"); await sleep(1200)
await clickText("Profile", { within: "nav" })
await shot("profile", "Profile tab", "src/screens/Profile.tsx", { settle: 1500 })
await clickText("Sign out", { within: ".profile" })
await shot("sign-out-sheet", "Sign-out confirmation sheet", "src/components/Sheet.tsx ('Sign out')", { settle: 900 })

const readme = ["# Reference screenshots", "", "Prototype at http://localhost:8443, headless Chrome, 390x844 viewport, deviceScaleFactor 2 (images are 780x1688). Each PNG is cropped to the `.phone` element.", "At a viewport <= 480px wide the studio chrome is hidden and the phone is full-bleed (no 7px border / rounded frame). Status bar 9:41 and home indicator are drawn inside the screenshot.", "Sample text is placeholder data only (email alex@example.com, code 482916).", "", ...log.map(([f, d, s]) => `- \`${f}\` - ${d}. Source: ${s}`), ""].join("\n")
fs.writeFileSync(path.join(ROOT, "README.md"), readme)
fs.writeFileSync(new URL("./missing.json", import.meta.url), JSON.stringify(missing))
await browser.close()
