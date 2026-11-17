#!/usr/bin/env node
// Fills the example blocks of docs/MOBILE_SMART_VIEW.md from the REAL captures in docs/examples/smartview/ (made by tools/smartview-capture.mjs), so no example is ever typed by hand.
//
//   node tools/smartview-doc-examples.mjs            rewrites every block in place (idempotent)
//   node tools/smartview-doc-examples.mjs --check    exits 1 when a block is out of date or names a missing capture (for CI)
//
// A block in the document is:   <!-- EX:<file name starts with>[:<keep N items of every array>] -->   ...generated...   <!-- /EX -->
// The generated text is the capture's request and reply as VALID JSON (comments never go inside JSON; they are the sentences around the block). An array cut to N items says so in a line under the block.
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const DOC = join(here, "..", "docs", "MOBILE_SMART_VIEW.md");
const DIR = join(here, "..", "docs", "examples", "smartview");
const files = readdirSync(DIR).filter((f) => /^\d{3}-.*\.json$/.test(f)).sort();

function cut(v, keep, path, notes) {
    if (Array.isArray(v)) {
        if (keep && v.length > keep) notes.push(`\`${path || "(top)"}\`: first ${keep} of ${v.length}`);
        return (keep ? v.slice(0, keep) : v).map((x, i) => cut(x, keep, `${path}[${i}]`, notes));
    }
    if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, cut(x, keep, path ? `${path}.${k}` : k, notes)]));
    return v;
}
const json = (v) => "```json\n" + JSON.stringify(v, null, 2) + "\n```";

function block(prefix, keepArg) {
    const f = files.find((x) => x.startsWith(prefix));
    if (!f) throw new Error(`no capture starts with "${prefix}"`);
    const d = JSON.parse(readFileSync(join(DIR, f), "utf8"));
    const keep = keepArg ? Number(keepArg) : 0, notes = [];
    const out = [`**${d.label}**: as ${d.as}; capture \`docs/examples/smartview/${f}\` **[VERIFIED: ran against a backend built from dev, 16 Nov 2026]**`, ""];
    if (d.request !== null && d.request !== undefined) out.push("Request:", json(cut(d.request, keep, "", notes)), "");
    if (d.events) out.push("Events pushed to each person's WebSocket:", json(cut(d.events, keep, "", notes)));
    else if (d.reply === null || d.reply === undefined) out.push("Capture:", json(cut(Object.fromEntries(Object.entries(d).filter(([k]) => !["label", "as"].includes(k))), keep, "", notes)));
    else if (d.reply.ok === false) out.push("Reply (refused):", json(cut(d.reply, keep, "", notes)));
    else out.push("Reply:", json(cut(d.reply, keep, "", notes)));
    if (notes.length) out.push("", `(Cut for reading, nothing else changed: ${notes.join("; ")}. The full reply is in the capture file.)`);
    return out.join("\n");
}

// A second kind of block pastes a part of the engine vectors: <!-- VEC:<path in vectors.json, dots>[:<keep N items>] --> ... <!-- /VEC -->
// (the output of the web's own functions, docs/examples/smartview-engine/vectors.json, made by tools/smartview-vectors.mjs)
const VEC = JSON.parse(readFileSync(join(here, "..", "docs", "examples", "smartview-engine", "vectors.json"), "utf8"));
function vecBlock(path, keepArg) {
    const sub = path.split(".").reduce((v, k) => (v === undefined ? v : v[k]), VEC);
    if (sub === undefined) throw new Error(`no vector at "${path}"`);
    const keep = keepArg ? Number(keepArg) : 0, notes = [];
    const head = `\`vectors.json\` → \`${path}\` **[VERIFIED: the web's own functions, run ${VEC.environment.madeOn.slice(0, 10)}, time zone ${VEC.environment.timeZone}, locale ${VEC.environment.locale}]**`;
    return [head, "", json(cut(sub, keep, "", notes)), ...(notes.length ? ["", `(Cut for reading: ${notes.join("; ")}.)`] : [])].join("\n");
}

const src = readFileSync(DOC, "utf8");
const re = /<!-- EX:([^:>\s]+)(?::(\d+))? -->[\s\S]*?<!-- \/EX -->/g;
const vre = /<!-- VEC:([^:>\s]+)(?::(\d+))? -->[\s\S]*?<!-- \/VEC -->/g;
let count = 0;
const next = src
    .replace(vre, (_m, path, keep) => { count += 1; return `<!-- VEC:${path}${keep ? `:${keep}` : ""} -->\n${vecBlock(path, keep)}\n<!-- /VEC -->`; })
    .replace(re, (_m, prefix, keep) => { count += 1; return `<!-- EX:${prefix}${keep ? `:${keep}` : ""} -->\n${block(prefix, keep)}\n<!-- /EX -->`; });
if (process.argv.includes("--check")) { if (next !== src) { console.error("MOBILE_SMART_VIEW.md has example blocks that are out of date: run tools/smartview-doc-examples.mjs"); process.exit(1); } console.log(`${count} example blocks up to date`); }
else { writeFileSync(DOC, next); console.log(`${count} example blocks written`); }
