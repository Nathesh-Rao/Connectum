// Runs inside the page. Returns a spec of the .phone element (coords relative to its top-left).
// Called twice (sample A/B) so the caller can flag animated elements.
export function extractSpec(opts = {}) {
  const phone = document.querySelector(".phone")
  const P = phone.getBoundingClientRect()
  const r2 = (n) => Math.round(n * 100) / 100
  const rel = (b) => ({ x: r2(b.left - P.left), y: r2(b.top - P.top), width: r2(b.width), height: r2(b.height) })
  const out = []
  const seenKey = new Map()

  const pathOf = (el) => {
    const parts = []
    for (let n = el; n && n !== phone; n = n.parentElement) {
      const i = Array.prototype.indexOf.call(n.parentElement.children, n)
      parts.push(n.tagName.toLowerCase() + (n.classList[0] ? "." + n.classList[0] : "") + "[" + i + "]")
    }
    return parts.reverse().join(">")
  }
  const hiddenByAncestor = (el) => {
    for (let n = el; n && n !== document.body; n = n.parentElement) {
      const s = getComputedStyle(n)
      if (s.display === "none" || s.visibility === "hidden" || parseFloat(s.opacity) === 0) return true
    }
    return false
  }
  const effOpacity = (el) => {
    let o = 1
    for (let n = el; n && n !== document.body; n = n.parentElement) o *= parseFloat(getComputedStyle(n).opacity)
    return r2(o)
  }
  const sidesBorder = (s) => {
    const sd = ["Top", "Right", "Bottom", "Left"].map((k) => `${s["border" + k + "Width"]} ${s["border" + k + "Style"]} ${s["border" + k + "Color"]}`)
    const none = (x) => /^0px /.test(x) || / none /.test(x)
    if (sd.every(none)) return "none"
    if (sd.every((x) => x === sd[0])) return sd[0]
    return { top: sd[0], right: sd[1], bottom: sd[2], left: sd[3] }
  }
  const styleOf = (el, s) => ({
    fontFamily: s.fontFamily, fontSize: s.fontSize, fontWeight: s.fontWeight, fontStyle: s.fontStyle,
    lineHeight: s.lineHeight, letterSpacing: s.letterSpacing, color: s.color, textAlign: s.textAlign,
    textTransform: s.textTransform, textDecoration: s.textDecorationLine,
    background: [s.backgroundColor, s.backgroundImage !== "none" ? s.backgroundImage : ""].filter((x) => x && x !== "rgba(0, 0, 0, 0)").join(" | ") || "transparent",
    border: sidesBorder(s), borderRadius: s.borderRadius, boxShadow: s.boxShadow,
    padding: s.padding, margin: s.margin, gap: s.gap === "normal" ? "normal" : s.gap,
    opacity: s.opacity, effectiveOpacity: effOpacity(el), transform: s.transform === "none" ? "none" : s.transform,
    filter: s.filter === "none" ? "none" : s.filter, display: s.display, position: s.position, zIndex: s.zIndex,
    overflow: s.overflow, flexDirection: s.display.includes("flex") ? s.flexDirection : undefined,
    justifyContent: s.display.includes("flex") || s.display.includes("grid") ? s.justifyContent : undefined,
    alignItems: s.display.includes("flex") || s.display.includes("grid") ? s.alignItems : undefined,
    cssAnimation: s.animationName !== "none" ? `${s.animationName} ${s.animationDuration} ${s.animationTimingFunction} x${s.animationIterationCount}` : undefined,
  })
  const hasVisual = (s) =>
    (s.backgroundColor !== "rgba(0, 0, 0, 0)") || s.backgroundImage !== "none" ||
    sidesBorder(s) !== "none" || s.boxShadow !== "none"

  const place = (b) => {
    // Zones inside the phone frame
    return b
  }
  const statusEl = phone.querySelector(".status")
  const homeEl = phone.querySelector(".home-indicator")
  const statusBox = statusEl ? rel(statusEl.getBoundingClientRect()) : null
  const homeBox = homeEl ? rel(homeEl.getBoundingClientRect()) : null
  const zoneOf = (box) => {
    const z = []
    if (statusBox && statusBox.width && box.y < statusBox.y + statusBox.height && box.y + box.height > statusBox.y) z.push("status-bar")
    if (homeBox && homeBox.width) {
      const top = homeBox.y - 12 // home-indicator margin-top
      if (box.y + box.height > top && box.y < P.height) z.push("home-indicator-area")
    }
    return z
  }
  const labelFor = (el, kind, text) => {
    const aria = el.getAttribute("aria-label"), cls = [...el.classList].slice(0, 2).join(".")
    if (kind === "text") return `text "${text.slice(0, 60)}"`
    if (kind === "input") return `input ${el.getAttribute("aria-label") || el.getAttribute("placeholder") || el.id || ""}`.trim()
    if (kind === "icon") return `icon ${aria || el.parentElement?.getAttribute("aria-label") || (el.parentElement?.className || "").toString().split(" ")[0] || ""} (in ${el.parentElement?.tagName.toLowerCase()}.${(el.parentElement?.className?.baseVal ?? el.parentElement?.className ?? "").toString().split(" ")[0]})`
    if (kind === "image") return `image ${el.getAttribute("alt") || el.getAttribute("src")}`
    if (kind === "button") return `button ${aria || (el.textContent || "").trim().slice(0, 40) || cls}`
    return `shape ${cls || el.tagName.toLowerCase()}`
  }
  const push = (el, kind, extra = {}) => {
    const b = el.getBoundingClientRect()
    if (!b.width && !b.height) return
    const s = getComputedStyle(el)
    const box = rel(b)
    const key = pathOf(el) + (extra.pseudo ? "::" + extra.pseudo : "") + (extra.suffix || "")
    let sample
    if (opts.sample && (kind === "text" || kind === "button" || kind === "input" || kind === "image")) {
      for (const [sel, why] of opts.sample) { if (el.closest(sel)) { sample = why; break } }
    }
    out.push({
      key, kind, label: extra.label ?? labelFor(el, kind, extra.text ?? ""), ...box,
      ...(sample ? { sampleContent: true, sampleKind: sample } : {}),
      zones: zoneOf(box), tag: el.tagName.toLowerCase(), classes: el.classList ? [...el.classList].join(" ") : "",
      ...(extra.text !== undefined ? { text: extra.text, textBox: extra.textBox } : {}),
      style: extra.style ?? styleOf(el, s),
      ...(extra.attrs ? { attrs: extra.attrs } : {}),
    })
  }

  const textBoxOf = (el) => {
    const range = document.createRange()
    const nodes = [...el.childNodes].filter((n) => n.nodeType === 3 && n.textContent.trim())
    if (!nodes.length) return null
    range.setStartBefore(nodes[0]); range.setEndAfter(nodes[nodes.length - 1])
    const rects = [...range.getClientRects()]
    // line count: group by top
    const tops = new Set(rects.map((r) => Math.round(r.top)))
    const rb = range.getBoundingClientRect()
    return { ...rel(rb), lines: tops.size, text: nodes.map((n) => n.textContent.replace(/\s+/g, " ").trim()).join(" ") }
  }

  const walk = (el) => {
    if (el.nodeType !== 1) return
    const tag = el.tagName.toLowerCase()
    if (["script", "style"].includes(tag)) return
    if (hiddenByAncestor(el)) return
    const b = el.getBoundingClientRect()
    const s = getComputedStyle(el)
    // pseudo elements with generated content (rings, dots, ...)
    for (const ps of ["::before", "::after"]) {
      const p = getComputedStyle(el, ps)
      if (p.content && p.content !== "none" && p.content !== "normal" && p.display !== "none") {
        const w = parseFloat(p.width), h = parseFloat(p.height)
        if (w > 0 && h > 0 && (p.backgroundColor !== "rgba(0, 0, 0, 0)" || p.backgroundImage !== "none" || p.borderTopWidth !== "0px")) {
          out.push({
            key: pathOf(el) + ps, kind: "shape", label: `shape ${[...el.classList][0] || tag}${ps}`, pseudo: ps,
            note: "pseudo-element; x/y are the parent's box + CSS offsets (inset:" + p.inset + ") — see style",
            ...rel(b), width: w, height: h, zones: [], tag, classes: [...el.classList].join(" "),
            style: {
              background: [p.backgroundColor, p.backgroundImage !== "none" ? p.backgroundImage : ""].filter((x) => x && x !== "rgba(0, 0, 0, 0)").join(" | ") || "transparent",
              border: `${p.borderTopWidth} ${p.borderTopStyle} ${p.borderTopColor}`, borderRadius: p.borderRadius, inset: p.inset, position: p.position, opacity: p.opacity,
            },
          })
        }
      }
    }
    if (tag === "svg" || el instanceof SVGSVGElement) {
      const big = b.width > 60 || b.height > 60
      if (!big) {
        push(el, "icon", { attrs: { viewBox: el.getAttribute("viewBox"), stroke: getComputedStyle(el).stroke, fill: getComputedStyle(el).fill, strokeWidth: getComputedStyle(el).strokeWidth, markup: el.innerHTML.replace(/\s+/g, " ").slice(0, 600) } })
        return
      }
      // illustration: record the svg, then every drawable child with its attributes
      push(el, "shape", { label: "svg illustration " + (el.getAttribute("class") || ""), attrs: { viewBox: el.getAttribute("viewBox") } })
      let i = 0
      el.querySelectorAll("circle,ellipse,rect,path,line,polyline,polygon,text,image").forEach((c) => {
        if (hiddenByAncestor(c)) return
        const cb = c.getBoundingClientRect()
        if (!cb.width && !cb.height) return
        const cs = getComputedStyle(c)
        const attrs = {}
        for (const a of c.attributes) if (!["style", "class"].includes(a.name)) attrs[a.name] = a.value.length > 200 ? a.value.slice(0, 200) + "…" : a.value
        const gOpacity = effOpacity(c)
        out.push({
          key: pathOf(el) + "#" + i++, kind: "shape", label: `svg ${c.tagName.toLowerCase()} ${c.id || c.getAttribute("class") || ""}`.trim(), ...rel(cb),
          zones: [], tag: c.tagName.toLowerCase(), classes: c.getAttribute("class") || "",
          style: { fill: cs.fill, stroke: cs.stroke, strokeWidth: cs.strokeWidth, strokeOpacity: cs.strokeOpacity, fillOpacity: cs.fillOpacity, opacity: cs.opacity, effectiveOpacity: gOpacity, transform: cs.transform === "none" ? (c.getAttribute("transform") || "none") : cs.transform, filter: cs.filter },
          attrs,
          ...(c.tagName.toLowerCase() === "text" ? { text: c.textContent.trim() } : {}),
        })
      })
      return
    }
    if (tag === "img") { push(el, "image", { attrs: { src: el.getAttribute("src"), objectFit: s.objectFit, naturalWidth: el.naturalWidth, naturalHeight: el.naturalHeight } }); return }
    if (["input", "textarea", "select"].includes(tag)) {
      const val = el.value
      push(el, "input", { text: val || undefined, attrs: { type: el.type, placeholder: el.placeholder || undefined, value: val ? "(set)" : "", maxLength: el.maxLength > 0 ? el.maxLength : undefined } })
      return
    }
    const own = textBoxOf(el)
    const visual = hasVisual(s)
    if (tag === "button") push(el, "button", { text: own?.text, textBox: own ? { x: own.x, y: own.y, width: own.width, height: own.height, lines: own.lines } : undefined })
    else if (own) push(el, "text", { text: own.text, textBox: { x: own.x, y: own.y, width: own.width, height: own.height, lines: own.lines } })
    else if (visual && b.width && b.height) push(el, el.getAttribute("role") === "separator" || (b.height <= 2 || b.width <= 2) ? "divider" : "shape")
    if (tag === "button" && own === null && !visual) { /* already pushed */ }
    else if (tag === "button" && own) { /* pushed with text */ }
    else if (own && visual) { /* text element also carries a box; one record holds both */ }
    for (const c of el.children) walk(c)
  }
  if (opts.scope) { const root = phone.querySelector(opts.scope); if (root) walk(root) }
  else for (const c of phone.children) walk(c)

  return {
    frame: { width: r2(P.width), height: r2(P.height), borderRadius: getComputedStyle(phone).borderRadius, background: getComputedStyle(phone).backgroundColor, border: sidesBorder(getComputedStyle(phone)), padding: getComputedStyle(phone).padding },
    statusBar: statusBox && statusBox.width ? { ...statusBox, visible: getComputedStyle(statusEl).visibility !== "hidden", padding: getComputedStyle(statusEl).padding, fontSize: getComputedStyle(statusEl).fontSize, content: statusEl.textContent } : null,
    homeIndicator: homeBox && homeBox.width ? { ...homeBox, visible: getComputedStyle(homeEl).visibility !== "hidden", background: getComputedStyle(homeEl).backgroundColor, borderRadius: getComputedStyle(homeEl).borderRadius, margin: getComputedStyle(homeEl).margin, bottomAreaTop: r2(homeBox.y - 12), note: "home-indicator area = from bottomAreaTop (indicator top minus its 12px margin) to the frame bottom" } : null,
    elements: out,
  }
}
