// Adds the missing screenshots and the remaining layout specs. Never rewrites an existing PNG.
// Run: node reference-screenshots/tools/run-more.mjs   (needs the dev server on :8443 and puppeteer-core)
import puppeteer from "puppeteer-core"
import fs from "node:fs"
import path from "node:path"

const ROOT = process.env.REF_ROOT ?? path.resolve(new URL("..", import.meta.url).pathname)
const SPECS = path.join(ROOT, "specs")
const extractSrc = fs.readFileSync(new URL("./extract.js", import.meta.url), "utf8").replace("export function", "function")
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const browser = await puppeteer.launch({ executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: true, args: ["--no-sandbox", "--hide-scrollbars"] })
const page = await browser.newPage()
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 })
const missing = []
const added = { png: [], spec: [] }
let nextPng = Math.max(...fs.readdirSync(ROOT).filter((f) => /^\d\d-.*\.png$/.test(f)).map((f) => +f.slice(0, 2))) + 1

// ---- hardcoded sample data: [css selector, kind]. First match wins; matches the element or any ancestor.
const SAMPLE = [
  [".conversation", "conversation-list-data"], [".workspace small", "sample-copy"],
  [".enterprise strong", "enterprise-name"], [".enterprise-choice", "enterprise-name"], [".enterprise-row", "enterprise-name"],
  [".identity-strip strong", "connectum-id"], [".profile h2", "person-name"], [".profile p", "connectum-id"], [".profile .setting:first-of-type", "enterprise-name"],
  [".avatar", "initials"], [".thread-name", "person-name"], [".thread .bubble", "message"], [".timestamp", "time"], [".thread .day", "date"],
  [".thread .notice", "group-notice"], [".unread-divider", "count"], [".typing", "person-name"],
  [".sc-strip span", "submission-id"], [".sc-field", "form-field-data"], [".sc-title", "form-title"], [".sc-more", "count"], [".sc-time", "time"],
  [".notification-card", "notification"], [".detail-card", "submission-data"],
  [".sum-card", "ai-answer"], [".sum-user", "user-prompt"], [".scope-chip", "person-name"], [".pinned-head strong", "summary-title"], [".pinned-text", "summary-text"],
  [".ai-user", "message"], [".ai-assistant", "ai-answer"], [".history-copy", "chat-history"], [".ai-suggestions .chip", "suggested-prompt"],
  [".forms-recent .chip", "form-name"], [".forms-list .setting", "form-name"],
]
// ---- animations (tokens from src/motion.ts: fast .19 base .32 slow .5 page .45 s; ease.out cubic-bezier(.25,.06,.12,1); spring 300/32/1; press 420/34/1)
const EO = "ease.out cubic-bezier(0.25,0.06,0.12,1)"
const SPRING = "spring stiffness 300, damping 32, mass 1"
const PRESS = "press spring stiffness 420, damping 34, mass 1"
const A = {
  tap: { element: "every non-row Button / tab / chip", effect: "whileTap scale 1 -> 0.97", timing: PRESS, source: "components/Button.tsx" },
  rise: (what, src) => ({ element: what, effect: "landing: opacity 0 -> 1, translateY 12px -> 0", timing: `0.32s (rows 0.19s) ${EO}; delay = min(index,8) x 0.055s`, source: src }),
  tabIn: { element: "whole screen (tab switch)", effect: "opacity 0 -> 1, translateY 8px -> 0 (outgoing fades 0.19s)", timing: `0.32s ${EO}`, source: "motion.ts screenVariants kind 'tab'" },
  pushIn: { element: "whole screen (push from Chats)", effect: "translateX 100% -> 0; outgoing screen shifts -25% under a 12% scrim", timing: `0.45s (duration.page) ${EO}`, source: "motion.ts screenVariants kind 'push'" },
  sheet: [
    { element: "sheet backdrop", effect: "opacity 0 -> 1 (exit reverses)", timing: `0.32s ${EO}`, source: "components/Sheet.tsx" },
    { element: "sheet panel", effect: "translateY 100% -> 0", timing: `${SPRING}; exit tween 0.32s ${EO}`, source: "components/Sheet.tsx" },
    { element: "sheet body content", effect: "opacity 0 -> 1 when the sheet name changes", timing: `0.19s ${EO}`, source: "components/Sheet.tsx" },
  ],
  navInd: { element: "bottom-nav active indicator (3px bar)", effect: "layoutId slide between tabs", timing: PRESS, source: "components/BottomNav.tsx" },
  chipInd: { element: "filter chip selected pill", effect: "layoutId slide between chips", timing: PRESS, source: "components/FilterChips.tsx" },
  card: [
    { element: ".sub-card", effect: "enter: opacity 0 -> 1, x +/-28px (sent from right, received from left), scale .98 -> 1; a freshly sent card also y +150px, scale .92", timing: SPRING, source: "components/FormCard.tsx" },
    { element: ".sub-card press", effect: "whileTap scale 0.985", timing: PRESS, source: "components/FormCard.tsx" },
    { element: ".sc-extra (+N more)", effect: "height 0 <-> auto with opacity", timing: `0.32s ${EO}`, source: "components/FormCard.tsx" },
    { element: ".sc-more chevron", effect: "rotate 0 <-> 180deg", timing: PRESS, source: "components/FormCard.tsx" },
    { element: ".fc-pulse", effect: "opacity [0,1,0,.8,0] highlight after send (1.4s, delay .5s) or edit (1.3s)", timing: "keyframes", source: "components/FormCard.tsx" },
  ],
  bubble: { element: ".bubble (message added after the screen settled)", effect: "opacity 0 -> 1, translateY 12px -> 0", timing: `0.32s ${EO}`, source: "components/conversation/ThreadView.tsx" },
  thinking: { element: "thinking dots (3)", effect: "opacity .4->1->.4 and y 0->-3->0, loop", timing: `0.9s ${"ease.inOut cubic-bezier(0.65,0,0.35,1)"} repeat forever, 0.15s stagger`, source: "components/conversation/SummaryPanel.tsx ThinkingDots" },
  stream: { element: "answer text", effect: "simulated streaming: 800 ms thinking, then 2 tokens every 38 ms", timing: "timers (useStream)", source: "state/use-stream.ts" },
  send: { element: "send button", effect: "scale .92 <-> 1 and fill opacity 0 <-> 1 when text is present", timing: `${PRESS}; fill 0.2s`, source: "AiComposer.tsx / SummaryPanel.tsx" },
}
const SHEET = A.sheet
const NAV = A.navInd

const mapNotes = {}
const navStates = {}

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
const clickSel = async (sel) => { const el = await page.$(sel); if (!el) throw new Error("no " + sel); await el.click() }
const closeSheet = async () => { await clickSel('.sheet [aria-label="Close"]'); await sleep(650) }

// png: false => the screenshot already exists (existing = its file stem). spec: {name, num?, scope?, sample?, anim, notes?}
async function cap({ png, existing, desc, src, spec, settle = 0 }) {
  if (settle) await sleep(settle)
  await page.evaluate(() => getSelection()?.removeAllRanges())
  let stem = existing
  if (png) {
    const num = String(nextPng++).padStart(2, "0")
    stem = `${num}-${png}`
    await (await page.$(".phone")).screenshot({ path: path.join(ROOT, `${stem}.png`) })
    added.png.push([`${stem}.png`, desc, src])
    console.log("png", stem)
  }
  if (!spec) return
  const opts = { scope: spec.scope, sample: [...(spec.sample ?? []), ...SAMPLE] }
  const run = () => page.evaluate(`(${extractSrc})(${JSON.stringify(opts)})`)
  const a = await run()
  await sleep(spec.gap ?? 600)
  const b = await run()
  const bm = new Map(b.elements.map((e) => [e.key, e]))
  let animated = 0
  for (const e of a.elements) {
    const o = bm.get(e.key)
    const ch = o && (["x", "y", "width", "height"].some((k) => Math.abs(o[k] - e[k]) > 0.05) || (o.style.transform ?? "") !== (e.style.transform ?? "") || (o.style.effectiveOpacity ?? "") !== (e.style.effectiveOpacity ?? ""))
    e.animated = !!(ch || e.style?.cssAnimation)
    if (ch) e.animatedSample = { atT0: { x: e.x, y: e.y, width: e.width, height: e.height, opacity: e.style.effectiveOpacity }, atT1: { x: o.x, y: o.y, width: o.width, height: o.height, opacity: o.style.effectiveOpacity } }
    if (e.animated) animated++
    delete e.key
  }
  const file = `${stem.slice(0, 2)}-${spec.name}`
  const out = {
    screen: spec.name, screenshot: `${stem}.png`, source: spec.src ?? src,
    viewport: { width: 390, height: 844, deviceScaleFactor: 2 }, coordinateSpace: "CSS px relative to the .phone frame top-left",
    ...(spec.scope ? { scope: spec.scope + " (only this element's subtree is listed; x/y are still frame-relative)" } : {}),
    sampleContentNote: "elements with sampleContent:true show hardcoded prototype data (names, messages, amounts, dates, counts, enterprise names); a real build must fetch or compute them. sampleKind says what the data is.",
    ...(spec.notes ? { notes: spec.notes } : {}),
    animations: spec.anim.flat(),
    ...a, animatedElementCount: animated,
    animatedNote: "animated=true: rect/transform/opacity changed between two samples ~0.6s apart or a CSS animation is set; the animations list is the authoritative description.",
    sampleContentCount: a.elements.filter((e) => e.sampleContent).length, elements: a.elements,
  }
  fs.writeFileSync(path.join(SPECS, `${file}.json`), JSON.stringify(out, null, 1))
  added.spec.push(`${file}.json`)
  console.log("spec", file, out.elements.length, "elements,", out.sampleContentCount, "sample")
  if (spec.nav) navStates[spec.nav] = a.elements.filter((e) => e.y > 700 && !e.sampleContent || e.y > 700)
}

// ===================== reach Chats =====================
await page.goto("http://localhost:8443/", { waitUntil: "networkidle0" })
await page.waitForSelector(".introduction", { timeout: 15000 })
await sleep(800)
await clickText("Skip")
await page.waitForSelector("#access-email")
await sleep(1200)
await page.type("#access-email", "alex@example.com")
await clickText("Sign in", { exact: false })
await page.waitForSelector(".otp-cells")
await sleep(1000)
await clickSel(".otp-cell input")
await page.keyboard.type("482916")
await page.mouse.click(5, 400)
await clickText("Verify", { exact: false })
await page.waitForSelector(".enterprise-page")
await sleep(1500)
await clickText("Agile Labs", { within: ".enterprise-list", exact: false })
await page.waitForSelector(".chat-scroll")
await sleep(1900)

// ===================== Chats =====================
await cap({ existing: "14-chats-home", desc: "", src: "", spec: { name: "chats-home", src: "src/screens/Chats.tsx", nav: "Chats", anim: [
  [{ element: "screen", effect: "enters from Enterprises: opacity 0 -> 1, translateY 16 -> 0 (outgoing fades 0.32s)", timing: `0.5s (duration.slow) ${EO}`, source: "motion.ts kind 'enter'" }],
  [A.rise("header, search row (Rise index 0/1), filter chips, pinned workspace, conversation rows (index 3+)", "screens/Chats.tsx, Landing.tsx")],
  [{ element: "conversation rows after a search/filter change", effect: "layout reflow, exit opacity 0, re-entering rows opacity 0 -> 1, y 6 -> 0", timing: `0.19s ${EO}; layout default`, source: "screens/Chats.tsx 'late' landing" }],
  [A.chipInd, A.tap],
] }, settle: 0 })
await cap({ existing: "14-chats-home", spec: { name: "bottom-nav", scope: "nav", nav: "Chats", src: "src/components/BottomNav.tsx", notes: "Tab 'Chats' active. Same nav, other tabs active, in bottom-nav-states.json (merged at the end).", anim: [[NAV, A.tap]] } })
// filter + search (new PNGs)
await clickText("Direct & Teams", { within: ".filters", exact: false })
await cap({ png: "chats-filter-direct-teams", desc: "Chats home with the 'Direct & Teams' filter selected", src: "src/screens/Chats.tsx, src/components/FilterChips.tsx", settle: 900 })
await clickText("All", { within: ".filters", exact: false }); await sleep(600)
await page.click(".search input"); await page.keyboard.type("pri"); await sleep(700)
await cap({ png: "chats-search-typed", desc: "Chats: search focused with 'pri' typed, list filtered to matches", src: "src/screens/Chats.tsx", settle: 500 })
await page.keyboard.type("zzz"); await sleep(800)
await cap({ png: "chats-search-no-results", desc: "Chats: search with no match ('No conversations found.') - the only empty state Chats has", src: "src/screens/Chats.tsx", settle: 400 })
await page.click(".search input"); await page.keyboard.press("End"); for (let i = 0; i < 8; i++) await page.keyboard.press("Backspace"); await sleep(1000)
await page.mouse.click(5, 400)
// sheets
await clickSel('[aria-label="New chat"]'); await sleep(900)
await cap({ existing: "15-chats-new-chat-sheet", spec: { name: "new-chat-sheet", src: "src/components/Sheet.tsx ('New Group / Chat')", sample: [[".sheet .setting", "person-name"]], anim: [SHEET, [A.tap]] } })
await closeSheet()
await clickSel(".enterprise"); await sleep(900)
await cap({ existing: "16-chats-enterprise-switcher-sheet", spec: { name: "enterprise-switcher-sheet", src: "src/components/Sheet.tsx ('Enterprises')", anim: [SHEET, [A.tap]] } })
await closeSheet()
await clickSel('[aria-label="Notifications"]'); await sleep(1100)
await cap({ existing: "17-notifications", spec: { name: "notifications", src: "src/screens/Notifications.tsx", notes: "Only the 'with items' state exists in the prototype: the single card is hardcoded; there is no empty list state.", anim: [[A.pushIn], [A.tap]] } })
await clickSel(".page-heading .icon-button"); await sleep(900)

// ===================== Conversation =====================
await clickText("Priya Sharma", { within: ".chat-scroll", exact: false })
await page.waitForSelector(".conv"); await sleep(1500)
await page.evaluate(() => { const t = document.querySelector(".thread"); t.scrollTop = t.scrollHeight })
await sleep(600)
await cap({ existing: "18-conversation-bottom", spec: { name: "conversation", src: "src/screens/Conversation.tsx, ThreadView.tsx", notes: "Header, incoming/outgoing bubbles (see 19 for the earlier part with the day divider and sent bubble), 'new messages' divider, typing row, composer (+, forms grid, input, mic).", anim: [[A.pushIn], [A.bubble], A.card.slice(0, 2), [{ element: "typing indicator", effect: "static text '... <name> is typing' (no animation)", timing: "-", source: "ThreadView.tsx" }], [A.tap]] } })
await page.evaluate(() => { const t = document.querySelector(".thread"); t.scrollTop = 0 }); await sleep(500)
await cap({ existing: "18-conversation-bottom", spec: { name: "conversation-top", src: "src/screens/Conversation.tsx, ThreadView.tsx", notes: "Thread scrolled to the top: date divider ('day'), group notice, incoming and outgoing bubbles with timestamps and the 'Read' note.", anim: [[A.bubble], [A.tap]] } })
await page.evaluate(() => document.querySelector(".sub-card.sent")?.scrollIntoView({ block: "center" })); await sleep(600)
const cardAnim = [A.card]
await cap({ existing: "19-conversation-sent-form-card", spec: { name: "form-card-sent", scope: ".card-row.sent", src: "src/components/FormCard.tsx (.sub-card.sent)", notes: "Collapsed: first 8 fields in two columns (left filled first), '+N more' row, time line. Sent = right-aligned with edit pencil in the strip.", anim: cardAnim } })
await clickSel(".sub-card.sent .sc-more"); await sleep(900)
await page.evaluate(() => document.querySelector(".sub-card.sent")?.scrollIntoView({ block: "center" })); await sleep(500)
await cap({ png: "conversation-sent-form-card-expanded", desc: "Conversation: the sent card expanded with 'Show less' (extra fields revealed)", src: "src/components/FormCard.tsx", spec: { name: "form-card-sent-expanded", scope: ".card-row.sent", src: "src/components/FormCard.tsx (.sub-card.sent, open)", anim: cardAnim } })
await clickSel(".sub-card.sent .sc-more"); await sleep(700)
await page.evaluate(() => { const t = document.querySelector(".thread"); t.scrollTop = t.scrollHeight }); await sleep(600)
await cap({ existing: "20-conversation-received-form-card", spec: { name: "form-card-received", scope: ".card-row.received", src: "src/components/FormCard.tsx (.sub-card.received)", notes: "Received = left-aligned, dark header strip, no edit pencil.", anim: cardAnim } })

// forms picker, form screen, commands
await clickSel('[aria-label="Forms"]'); await sleep(1300)
await cap({ existing: "21-forms-picker-sheet", spec: { name: "forms-picker-sheet", src: "src/components/sheets/FormsPicker.tsx", anim: [SHEET, [A.rise("Recent chips, form rows", "FormsPicker.tsx (Landing + Rise)")], [A.tap]] } })
await clickText("Clinical examination - Ortho", { within: ".sheet", exact: false })
await page.waitForSelector(".form-screen"); await sleep(1600)
const formAnim = [
  [{ element: "form backdrop", effect: "opacity 0 -> 1", timing: `0.32s ${EO}`, source: "FormScreen.tsx" }, { element: ".form-screen panel", effect: "translateY 100% -> 0", timing: `${SPRING}; exit tween 0.45s ${EO}`, source: "FormScreen.tsx" }],
  [A.rise("form head and each field (Rise index 0..n)", "FormScreen.tsx")],
  [{ element: "'This field is required' text", effect: "opacity 0 -> 1, translateY -4 -> 0 (exit opacity)", timing: `0.19s ${EO}`, source: "FormScreen.tsx" }, A.tap],
]
await cap({ existing: "22-form-screen-empty", spec: { name: "form-screen-empty", src: "src/components/FormScreen.tsx", notes: "Form 'Clinical examination - Ortho'; field list and defaults are sample form definitions.", sample: [[".form-head h2", "form-title"], [".form-field label", "form-definition"], [".form-control select, .form-control input[value]", "form-default"]], anim: formAnim } })
await clickText("Done", { within: ".form-screen" }); await sleep(700)
await cap({ existing: "23-form-screen-errors", spec: { name: "form-screen-errors", src: "src/components/FormScreen.tsx", sample: [[".form-head h2", "form-title"], [".form-field label", "form-definition"]], anim: formAnim } })
await clickSel('.form-screen [aria-label="Cancel"]'); await sleep(900)
await clickSel(".composer input"); await page.keyboard.type("#"); await sleep(1000)
await cap({ existing: "24-commands-sheet", spec: { name: "commands-sheet", src: "src/components/Sheet.tsx ('Commands')", sample: [[".sheet .setting", "sample-command"], [".sheet small", "sample-copy"]], anim: [SHEET, [A.tap]] } })
await closeSheet()
await page.click(".composer input", { clickCount: 3 }); await page.keyboard.press("Backspace"); await page.mouse.click(5, 600); await sleep(300)

// ===================== Received card with +N more (search other threads) =====================
let foundReceivedMore = false
for (const who of ["Arjun Mehta", "Design Collective", "Product & Engineering"]) {
  await clickSel(".thread-header .icon-button"); await sleep(1100)
  await clickText(who, { within: ".chat-scroll", exact: false }); await page.waitForSelector(".conv"); await sleep(1300)
  const has = await page.evaluate(() => { const m = document.querySelector(".sub-card.received .sc-more"); if (m) m.scrollIntoView({ block: "center" }); return !!m })
  if (has) {
    foundReceivedMore = true; await sleep(600)
    await cap({ png: "conversation-received-form-card-collapsed", desc: `Conversation (${who}): a RECEIVED card with '+N more' collapsed`, src: "src/components/FormCard.tsx", spec: { name: "form-card-received-more", scope: ".card-row.received", src: "src/components/FormCard.tsx", anim: cardAnim } })
    await clickSel(".sub-card.received .sc-more"); await sleep(900)
    await page.evaluate(() => document.querySelector(".sub-card.received")?.scrollIntoView({ block: "center" })); await sleep(500)
    await cap({ png: "conversation-received-form-card-expanded", desc: `Conversation (${who}): the same received card expanded`, src: "src/components/FormCard.tsx", spec: { name: "form-card-received-expanded", scope: ".card-row.received", src: "src/components/FormCard.tsx", anim: cardAnim } })
    break
  }
}
if (!foundReceivedMore) missing.push("No received form card in any seeded thread has a '+N more' row (received cards have <= 8 fields), so received collapsed/expanded variants with +N more do not exist.")
await clickSel(".thread-header .icon-button"); await sleep(1100)
await clickText("Priya Sharma", { within: ".chat-scroll", exact: false }); await page.waitForSelector(".conv"); await sleep(1300)

// ===================== Summarise =====================
const sumAnim = [
  [{ element: ".sum-panel", effect: "height 0 -> 60% of chat (or 94% when dragged); chat behind scales 1 -> .965 and dims", timing: `${SPRING}; exit tween 0.32s ${EO}; drag snaps to 0/60%/94% with the same spring`, source: "SummaryPanel.tsx, Conversation.tsx" }],
  [{ element: "title row", effect: "opacity 0 -> 1, translateY 12 -> 0", timing: `0.32s ${EO}, delay 0.12s`, source: "SummaryPanel.tsx" }],
  [A.send, A.thinking, A.stream, { element: "answer card / follow-ups / Copy+Pin actions", effect: "opacity 0 -> 1, translateY 12 -> 0 (actions: opacity only)", timing: `card ${SPRING}; others 0.32s ${EO}`, source: "SummaryPanel.tsx" }, { element: ".sum-scope-hint", effect: "height auto <-> 0 with opacity", timing: `0.32s ${EO}`, source: "SummaryPanel.tsx" }, A.tap],
]
const sumSample = [[".sum-hint", "sample-copy"]]
await clickSel('[aria-label="Summarise this chat"]'); await sleep(1600)
await cap({ existing: "25-summarise-60", spec: { name: "summarise-panel-60-empty", src: "src/components/conversation/SummaryPanel.tsx", sample: sumSample, anim: sumAnim } })
async function dragGrip(dy) {
  const g = await (await page.$(".sum-grip")).boundingBox()
  const x = g.x + g.width / 2, y0 = g.y + 12
  await page.mouse.move(x, y0); await page.mouse.down()
  const n = 14
  for (let i = 1; i <= n; i++) { await page.mouse.move(x, y0 + (dy * i) / n); await sleep(16) }
  await page.mouse.up(); await sleep(1100)
}
await dragGrip(-420)
await cap({ existing: "26-summarise-full", spec: { name: "summarise-panel-full-empty", src: "src/components/conversation/SummaryPanel.tsx", sample: sumSample, anim: sumAnim } })
await clickText("Summarise today", { within: ".sum-chips", exact: false })
await sleep(5200) // thinking 0.8s + streaming
await page.evaluate(() => document.querySelector(".sum-body")?.scrollTo(0, 0)); await sleep(400)
await cap({ png: "summarise-full-answer", desc: "Summarise panel at full height with a finished answer (Copy / Pin to chat actions)", src: "src/components/conversation/SummaryPanel.tsx", spec: { name: "summarise-panel-full-answer", src: "src/components/conversation/SummaryPanel.tsx", sample: sumSample, anim: sumAnim } })
await dragGrip(300)
await cap({ png: "summarise-60-answer", desc: "Summarise panel back at 60% with the answer", src: "src/components/conversation/SummaryPanel.tsx", spec: { name: "summarise-panel-60-answer", src: "src/components/conversation/SummaryPanel.tsx", sample: sumSample, anim: sumAnim } })
await clickText("Pin to chat", { within: ".sum-panel", exact: false }); await sleep(1500)
const pinAnim = [[{ element: ".pinned card", effect: "height 0 <-> auto with opacity (intentional exception to transform-only)", timing: `0.32s ${EO}`, source: "PinnedSummary.tsx" }, { element: ".pinned-text", effect: "height/opacity on collapse", timing: `0.32s ${EO}`, source: "PinnedSummary.tsx" }, { element: "chevron", effect: "rotate 0 <-> 180deg", timing: PRESS, source: "PinnedSummary.tsx" }, A.tap]]
await cap({ png: "conversation-pinned-summary", desc: "Conversation with a pinned summary card under the header (expanded)", src: "src/components/conversation/PinnedSummary.tsx", spec: { name: "pinned-summary-card", scope: ".pinned", src: "src/components/conversation/PinnedSummary.tsx", anim: pinAnim } })
await clickSel('[aria-label="Collapse summary"]'); await sleep(800)
await cap({ png: "conversation-pinned-summary-collapsed", desc: "Pinned summary folded to its title row", src: "src/components/conversation/PinnedSummary.tsx", spec: { name: "pinned-summary-card-collapsed", scope: ".pinned", src: "src/components/conversation/PinnedSummary.tsx", anim: pinAnim } })
await clickSel('[aria-label="Remove pinned summary"]'); await sleep(700)
await clickSel(".thread-header .icon-button"); await sleep(1200)

// ===================== AI =====================
await clickText("AI Agents", { within: "nav" })
await sleep(1600)
const aiAnim = [[A.tabIn], [A.rise("logo, 'How can I help?', hint, suggestion chips", "AiEmpty.tsx (Rise 0..)")], [{ element: ".ai-empty (when first message is sent)", effect: "exit: opacity 0, y -14, scale .98", timing: `0.32s ease.in cubic-bezier(0.4,0,1,1)`, source: "AiEmpty.tsx" }], [A.send, A.tap]]
await cap({ existing: "27-ai-agents-empty", spec: { name: "ai-agents-empty", nav: "AI Agents", src: "src/screens/AiAgents.tsx, components/ai/*", anim: aiAnim } })
await cap({ existing: "27-ai-agents-empty", spec: { name: "bottom-nav-ai", scope: "nav", nav: "AI Agents", src: "src/components/BottomNav.tsx", anim: [[NAV]] } })
await clickSel(".ai-suggestions .chip"); await sleep(1700)
await cap({ existing: "28-ai-agents-conversation", spec: { name: "ai-agents-conversation", gap: 100, src: "src/components/ai/AiThread.tsx", notes: "Captured mid-stream (~1.7s after sending): answer text length depends on timing; positions of later lines vary.", anim: [[{ element: ".ai-user bubble", effect: "opacity 0 -> 1, y 12 -> 0, scale .97 -> 1", timing: SPRING, source: "AiThread.tsx" }, { element: ".ai-assistant", effect: "opacity 0 -> 1, y 12 -> 0", timing: "0.32s (default easing)", source: "AiThread.tsx" }, A.thinking, { element: "answer text", effect: "streamed: thinking ~0.8s, then 2 tokens per tick", timing: "ai-store timers", source: "state/ai-store.ts" }, { element: "Copy/regenerate/feedback icons", effect: "icon swap scale .6 -> 1 + opacity (0.19s); feedback pop", timing: `0.19s; ${PRESS}`, source: "AiThread.tsx" }, A.send, A.tap]] } })
await sleep(4500)
await page.click(".ai-pill"); await sleep(1000)
await cap({ png: "ai-model-sheet", desc: "AI model picker sheet (Auto / Fast / Thinking)", src: "src/components/sheets/AiSheets.tsx (AiModel)", spec: { name: "model-picker-sheet", src: "src/components/sheets/AiSheets.tsx (AiModel)", anim: [SHEET, [A.tap]] } })
await closeSheet()
await clickSel('[aria-label="History"]'); await sleep(1100)
await cap({ png: "ai-history-sheet", desc: "AI history sheet (search past chats, list)", src: "src/components/sheets/AiSheets.tsx (AiHistory)", spec: { name: "ai-history-sheet", src: "src/components/sheets/AiSheets.tsx (AiHistory)", anim: [SHEET, [A.rise("search, history rows", "AiSheets.tsx (Landing)")], [A.tap]] } })
await closeSheet()

// ===================== Submissions, Profile =====================
await clickText("Submissions", { within: "nav" }); await sleep(1600)
await cap({ existing: "29-submissions-list", spec: { name: "submissions-list", nav: "Submissions", src: "src/screens/Submissions.tsx, SubmissionsLayout.tsx", anim: [[A.tabIn], [A.rise("heading, filter chips, cards", "SubmissionsLayout.tsx")], [A.chipInd, A.tap]] } })
await cap({ existing: "29-submissions-list", spec: { name: "bottom-nav-submissions", scope: "nav", nav: "Submissions", src: "src/components/BottomNav.tsx", anim: [[NAV]] } })
await clickSel(".detail-card"); await page.waitForSelector(".page-heading"); await sleep(1600)
await cap({ existing: "30-submission-detail", spec: { name: "submission-detail", src: "src/screens/SubmissionDetail.tsx", anim: [[A.pushIn], [A.rise("heading, chips, detail card", "SubmissionsLayout.tsx")], [A.tap]] } })
await clickSel(".page-heading .icon-button"); await sleep(1100)
await clickSel(".thread-header .icon-button"); await sleep(1200)
await clickText("Profile", { within: "nav" }); await sleep(1600)
await cap({ existing: "31-profile", spec: { name: "profile", nav: "Profile", src: "src/screens/Profile.tsx", anim: [[A.tabIn], [A.rise("heading, settings rows (index 1..4)", "Profile.tsx")], [A.tap]] } })
await cap({ existing: "31-profile", spec: { name: "bottom-nav-profile", scope: "nav", nav: "Profile", src: "src/components/BottomNav.tsx", anim: [[NAV]] } })
await clickText("Sign out", { within: ".profile" }); await sleep(1000)
await cap({ existing: "32-sign-out-sheet", spec: { name: "signout-sheet", src: "src/components/Sheet.tsx ('Sign out')", anim: [SHEET, [A.tap]] } })

fs.writeFileSync(path.join(SPECS, "14-bottom-nav-states.json"), JSON.stringify({ note: "Bottom nav elements (y>700) with each tab active; frame-relative CSS px. Also see NN-bottom-nav*.json for the full per-state specs.", states: navStates }, null, 1))
// README lines for new PNGs
if (added.png.length) {
  const rd = fs.readFileSync(path.join(ROOT, "README.md"), "utf8").trimEnd()
  fs.writeFileSync(path.join(ROOT, "README.md"), rd + "\n" + added.png.map(([f, d, s]) => `- \`${f}\` - ${d}. Source: ${s}`).join("\n") + "\n")
}
fs.writeFileSync(new URL("./run-more.result.json", import.meta.url), JSON.stringify({ added, missing }, null, 1))
console.log(JSON.stringify({ missing }, null, 1))
await browser.close()
