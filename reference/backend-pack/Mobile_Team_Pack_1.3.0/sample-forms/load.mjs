// Loads the sample forms of docs/sample-forms/ into an organisation: one form per feature (calc, rule, condition, cascading drop down, fetch, selection and fill, toggle, file, a grid with a
// total, dates) so a client (the mobile app) can be built and tested against forms that are known to work. Safe to run again: forms are saved over themselves, the sample records are
// added only when the colour list is empty.
//   node tools/sample-forms/load.mjs --base http://HOST:PORT --user NAME --token TOKEN [--api-base http://HOST:PORT]        (the session of an ADMINISTRATOR; use a test organisation)
// --api-base also loads the samples that need an API (docs/sample-forms/needs-setup/): two APIs and two forms, using the service at that address (tools/sample-forms/stand-in-api.mjs is one).
// Needs Node 22 or newer. See docs/sample-forms/README.md.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { connect, parseArgs } from "../e2e-kit/new-device.mjs";

export const DIR = fileURLToPath(new URL("../../docs/sample-forms/", import.meta.url));
const readJson = (name) => JSON.parse(fs.readFileSync(path.join(DIR, name), "utf8"));

/**
 * Saves every sample form (and an option for each, so people can open and fill it) and the sample records. `sd(action, args)` makes one call and answers {ok, data|error}.
 * -> { forms: [{name, ok, error?}], records: {form: number added} }
 */
export async function loadSamples(sd, log = () => {}, { apiBase } = {}) {
  const index = readJson("index.json");
  const out = { forms: [], records: {} };
  for (const f of index.forms) {
    const def = readJson(f.file);
    const saved = await sd("admin.tstruct.save", def);
    if (!saved.ok) { out.forms.push({ name: def.name, ok: false, error: `${saved.error?.code}: ${saved.error?.message}` }); log(`FAIL  ${def.name}: ${saved.error?.message}`); continue; }
    const opt = await sd("admin.option.save", { id: `${def.name}_option`, caption: def.caption, type: "data_input", target: def.name });
    out.forms.push({ name: def.name, ok: opt.ok, ...(opt.ok ? {} : { error: `option: ${opt.error?.code}: ${opt.error?.message}` }) });
    log(`${opt.ok ? "ok  " : "FAIL"}  ${def.name}${opt.ok ? "" : `: ${opt.error?.message}`}`);
  }
  if (apiBase) {
    const base = String(apiBase).replace(/\/+$/, "");
    const fill = (obj) => JSON.parse(JSON.stringify(obj).replaceAll("{{API_BASE}}", base));
    const { about: _a1, ...list } = fill(readJson("needs-setup/api_sample_list.json")), { about: _a2, ...person } = fill(readJson("needs-setup/api_sample_person.json"));
    for (const api of [list, person]) {
      const r = await sd("admin.api.save", api);
      out.forms.push({ name: `api:${api.name}`, ok: r.ok, ...(r.ok ? {} : { error: `${r.error?.code}: ${r.error?.message}` }) });
      log(`${r.ok ? "ok  " : "FAIL"}  API ${api.name}${r.ok ? "" : `: ${r.error?.message}`}`);
    }
    for (const file of ["sample_api_choice.json", "sample_api_fetch.json"]) {
      const def = readJson(`needs-setup/${file}`);
      const saved = await sd("admin.tstruct.save", def);
      const opt = saved.ok ? await sd("admin.option.save", { id: `${def.name}_option`, caption: def.caption, type: "data_input", target: def.name }) : saved;
      out.forms.push({ name: def.name, ok: opt.ok, ...(opt.ok ? {} : { error: `${opt.error?.code}: ${opt.error?.message}` }) });
      log(`${opt.ok ? "ok  " : "FAIL"}  ${def.name}${opt.ok ? "" : `: ${opt.error?.message}`}`);
    }
  }
  for (const [form, records] of Object.entries(index.records || {})) {
    const have = await sd("records.list", { tstruct: form, limit: 1 });
    if (have.ok && have.data.total > 0) { out.records[form] = 0; log(`${form}: already has records, none added`); continue; }
    let added = 0;
    for (const values of records) { const r = await sd("tstruct.submit", { name: form, values }); if (r.ok) added++; else log(`FAIL  ${form} record: ${r.error?.message}`); }
    out.records[form] = added;
    log(`${form}: ${added} sample record(s) added`);
  }
  return out;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  let a;
  try { a = parseArgs(["load", ...process.argv.slice(2)]); } catch (e) { console.error(e.message); process.exit(2); }
  if (!a.base || !a.user || !a.token) { console.error("usage: load.mjs --base http://HOST:PORT --user NAME --token TOKEN"); process.exit(2); }
  let conn;
  try { conn = await connect({ base: a.base, user: a.user, token: a.token }); } catch (e) { console.error(`ERROR: ${e.message}`); process.exit(1); }
  try {
    const r = await loadSamples(conn.sd, console.log, { apiBase: a["api-base"] });
    const bad = r.forms.filter((f) => !f.ok).length;
    console.log(bad ? `\n${bad} form(s) were not loaded.` : `\nAll ${r.forms.length} sample forms are loaded.`);
    process.exit(bad ? 1 : 0);
  } finally { conn.close(); }
}
