// An optional auto value on a field, written in the same expression language as a rule: { expr }. The form works it out from the other fields and fills the field in,
// e.g. on a "Group" drop down with the options Adult and Minor: IIF(age>18,"Adult","Minor"). The person cannot type in it. Pure JavaScript, shared by the web studio and
// the chat app, like fieldRule.js.
//
// * It is worked out again after every change, so it always matches the fields it reads. A field that reads another auto value is worked out after it.
// * While a field it reads is empty it stays empty (an empty number would otherwise count as 0, and everyone would start as "Minor").
// * The answer is made to fit the kind of field: text as it is; a number must be a number (a whole number a whole one); a date as dd/mm/yyyy; a drop down must be one of
//   its options (any capitals) or the field stays empty.
// * Fields that read each other in a circle settle after a few passes and never loop for ever.
// * In a grid section the field is worked out in every row, from the other cells of that row and from the fields outside the grids. A field outside can read a whole
//   column, e.g. Total(lineTotal), and is worked out again when the rows change.
import { evaluateExpression, getRuleGlobals, bareGlobalName } from './fieldRule.js';

export const CALC_EXPR_MAX = 500;
export const CALC_TYPES = ['text', 'wholeNumber', 'number', 'date', 'list'];
const kindOf = (f) => String(f?.type ?? '').toLowerCase();   // the studio says wholeNumber, the server wholenumber
const CALC_KINDS = CALC_TYPES.map((x) => x.toLowerCase());

export const hasCalc = (f) => !!(f && f.calc && String(f.calc.expr ?? '').trim());
export const canCalc = (f) => !!f && CALC_KINDS.includes(kindOf(f)) && !f.multi;

const isEmpty = (v) => v === undefined || v === null || v === '' || (Array.isArray(v) && v.length === 0);
const same = (a, b) => String(a ?? '') === String(b ?? '');
const LITERAL = /"[^"]*"|'[^']*'/g;
const WORD = /[A-Za-z_]\w*/g;

// The ids (as the form calls them) of the fields an expression reads: words that are a field id, apart from a function name (a word followed by "(") and text in quotes.
export function usedFields(expr, ids) {
  const byLower = new Map(ids.map((i) => [String(i).toLowerCase(), i]));
  const text = String(expr ?? '').replace(LITERAL, '""');
  const out = new Set();
  let m;
  WORD.lastIndex = 0;
  while ((m = WORD.exec(text))) {
    if (/^\s*\(/.test(text.slice(WORD.lastIndex))) continue;
    const id = byLower.get(m[0].toLowerCase());
    if (id !== undefined) out.add(id);
  }
  return [...out];
}

// What the parser answered, made to fit the field: the value to put in it, or '' for "nothing".
export function fitCalc(field, raw) {
  if (raw === null || raw === undefined) return '';
  const kind = kindOf(field);
  if (typeof raw === 'boolean') return kind === 'text' ? String(raw) : '';
  const text = String(raw).trim();
  if (text === '') return '';
  switch (kind) {
    case 'text':
      return text;
    case 'wholenumber':
    case 'number': {
      const n = Number(text);
      if (!Number.isFinite(n)) return '';
      if (kind === 'wholenumber' && !Number.isInteger(n)) return '';
      return String(n);
    }
    case 'date': {
      const dmy = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(text);
      if (dmy) return `${dmy[3]}-${dmy[2].padStart(2, '0')}-${dmy[1].padStart(2, '0')}`;
      return /^\d{4}-\d{2}-\d{2}$/.test(text) ? text : '';
    }
    case 'list': {
      const hit = (field.options || []).find((o) => String(o).trim().toLowerCase() === text.toLowerCase());
      return hit === undefined ? '' : hit;
    }
    default:
      return '';
  }
}

// ---- remembering answers --------------------------------------------------------------------------------------------------------------------
// An expression is worked out again only when something it reads has changed. The answer is remembered under the values of the names the expression mentions (every
// word in it, also inside quotes: Total("line") reads the column), and under today's date (some functions read the clock). A calculation over a long grid is then
// done once per change of its column instead of once per pass and per row. Expressions that read the time of day are never remembered.
const MEMORY = new Map(); // `${field id}\u0001${expression}` -> Map(inputs -> answer)
const MEMORY_FIELDS = 500;
const MEMORY_PER_FIELD = 400;
const WORDS = new Map(); // expression -> the lower-case words in it
const ANY_WORD = /[A-Za-z_]\w*/g;
const CLOCK = /\btime\s*\(/i;

const wordsOf = (expr) => {
  let w = WORDS.get(expr);
  if (!w) {
    if (WORDS.size > 2000) WORDS.clear();
    w = [...new Set((expr.match(ANY_WORD) || []).map((x) => x.toLowerCase()))];
    WORDS.set(expr, w);
  }
  return w;
};
const part = (v) => (v === undefined || v === null ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v));

// A calculation that is only a name (`login_employeeCode`, `firstName`) copies that value as it is. It is not handed to the parser, which reads digits as a number: that
// turned the code 0012 into 12, a code of 18 digits into a rounded number, and a person with no code into 0. -> the text, or undefined when the formula is more than a name.
const BARE = /^\s*([A-Za-z_]\w*)\s*$/;
function copied(expr, cur, names) {
  const m = BARE.exec(expr);
  if (!m) return undefined;
  const w = m[1].toLowerCase();
  const k = names.get(w);
  if (k !== undefined) { const v = cur[k]; return Array.isArray(v) || (v && typeof v === 'object') ? undefined : part(v); }
  const g = getRuleGlobals();
  const bare = bareGlobalName(w);
  for (const key in g) if (key.toLowerCase() === bare) return part(g[key]);
  return undefined;
}

// the answer of one auto value, remembered
function answer(id, expr, cur, names, columns) {
  const plain = copied(expr, cur, names);
  if (plain !== undefined) return plain;
  if (CLOCK.test(expr)) return evaluateExpression(expr, cur);
  const sig = `${new Date().toDateString()}\u0002${wordsOf(expr).map((w) => {
    const k = names.get(w);
    if (k !== undefined) return part(cur[k]);
    const col = columns && columns.get(w);
    if (col) { const rows = cur[col[0]]; return Array.isArray(rows) ? rows.map((r) => part(r && r[col[1]])).join('\u0003') : ''; }
    const g = getRuleGlobals();   // the signed-in person's own details (employeeCode, department ...) when the word is one of them
    const bare = bareGlobalName(w);
    for (const k in g) if (k.toLowerCase() === bare) return part(g[k]);
    return '';
  }).join('\u0001')}`;
  const key = `${id}\u0001${expr}`;
  let m = MEMORY.get(key);
  if (!m) {
    if (MEMORY.size >= MEMORY_FIELDS) MEMORY.clear();
    m = new Map();
    MEMORY.set(key, m);
  }
  if (m.has(sig)) return m.get(sig);
  const out = evaluateExpression(expr, cur);
  if (m.size >= MEMORY_PER_FIELD) m.clear();
  m.set(sig, out);
  return out;
}

/**
 * The values with every auto value worked out. `fields` are the form's ordinary fields (not the fields of grid rows); `idOf` says how the form names a field
 * (`id` in the studio, `name` in the chat app); `extraIds` are other names the expressions may read (the form outside a grid, for a row); `columns` maps the
 * (lower-case) id of a grid field to [section key, field id], for an expression outside the grid that reads a whole column. Returns the same object when nothing needs
 * working out or nothing changed.
 */
export function applyCalcs(fields, values, idOf = (f) => f.id, extraIds = [], columns = null) {
  const calcs = fields.filter(hasCalc);
  if (!calcs.length) return values;
  const ids = [...fields.map(idOf), ...extraIds];
  const names = new Map([...Object.keys(values), ...ids].map((k) => [String(k).toLowerCase(), k]));
  let cur = values;
  for (let pass = 0; pass <= calcs.length; pass += 1) {
    let changed = false;
    for (const f of calcs) {
      const id = idOf(f);
      const reads = usedFields(f.calc.expr, ids).filter((x) => x !== id);
      // a field cannot read itself: a word in its own formula that is also its own id means the signed-in person's detail of that name (employeeCode in the field employeeCode)
      const { [id]: _own, ...view } = cur;
      const others = new Map(names); others.delete(String(id).toLowerCase());
      const next = reads.some((x) => isEmpty(cur[x])) ? '' : fitCalc(f, answer(id, f.calc.expr, view, others, columns));
      if (!same(cur[id], next)) {
        cur = { ...cur, [id]: next };
        changed = true;
      }
    }
    if (!changed) break;
  }
  return cur;
}

// One row of a grid section: its auto values worked out from the row's own cells and from `outer` (the form's values outside the grids). The same row object back when
// nothing changed.
export function applyRowCalcs(fields, row, outer, idOf = (f) => f.id) {
  const calcs = fields.filter(hasCalc);
  if (!calcs.length) return row;
  const ctx = applyCalcs(fields, { ...outer, ...row }, idOf, Object.keys(outer));
  let out = row;
  for (const f of calcs) {
    const id = idOf(f);
    if (!same(row[id], ctx[id])) out = { ...out, [id]: ctx[id] };
  }
  return out;
}

/**
 * Every auto value of the form: the ordinary fields, then each row of each grid section, again until nothing moves (a total outside reads a column that was just worked
 * out, a cell reads a field outside that was too). `grids` is [{ id, fields }] with the section's key in the values and the fields of its rows. The same object back when
 * nothing changed.
 */
export function applyFormCalcs(fields, grids, values, idOf = (f) => f.id) {
  const gridIds = new Set(grids.map((g) => g.id));
  let cur = values;
  const columns = new Map();
  for (const g of grids) for (const f of g.fields) columns.set(String(idOf(f)).toLowerCase(), [g.id, idOf(f)]);
  for (let pass = 0; pass < 4; pass += 1) {
    let next = applyCalcs(fields, cur, idOf, [], columns);
    const outer = Object.fromEntries(Object.entries(next).filter(([k]) => !gridIds.has(k)));
    for (const g of grids) {
      const rows = next[g.id];
      if (!Array.isArray(rows) || !g.fields.some(hasCalc)) continue;
      const done = rows.map((r) => applyRowCalcs(g.fields, r, outer, idOf));
      if (done.some((r, i) => r !== rows[i])) next = { ...next, [g.id]: done };
    }
    if (next === cur) break;
    cur = next;
  }
  return cur;
}
