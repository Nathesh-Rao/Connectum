// An optional rule on a field, written in the Axpert expression language (AxExpReactParser). A rule is { expr, message }: it must come out true for the
// value to be accepted, e.g. Length(phone)=10, age>=18 && qty>0, CheckEmail(email). It sees every field of the form by its id (the same name the person
// sees in the builder), and in a grid cell the fields of that row (on an ordinary field the grid's rows are there too, row by row, for Total(qty) and the like). Pure JavaScript with no imports from the app, so the web studio and the chat app share it.
import { RegisterVariable, Evaluate } from './axExpParser.js';

export const RULE_EXPR_MAX = 500;
export const RULE_MSG_MAX = 200;

// The signed-in person's own details, by the name of the global variable (employeeCode, department, email ...): an expression may read them as it reads a field of the
// form, e.g. department="Sales" or Length(employeeCode)>3. The app sets them once the person is known (setRuleGlobals); a field of the form with the same name wins.
export const GLOBAL_PREFIX = 'login_';
// forms saved while the prefix was `global_` keep working: that spelling is still read, as the same thing (the builder writes and suggests `login_`)
export const LEGACY_GLOBAL_PREFIX = 'global_';
// the name of a signed-in person's detail with the prefix taken off, in either spelling (a word that has neither prefix is returned as it is)
export const bareGlobalName = (w) => (w.startsWith(GLOBAL_PREFIX) ? w.slice(GLOBAL_PREFIX.length) : w.startsWith(LEGACY_GLOBAL_PREFIX) ? w.slice(LEGACY_GLOBAL_PREFIX.length) : w);
let GLOBALS = {};
let GLOBALS_VERSION = 0;
export const setRuleGlobals = (values) => {
  const next = {};
  for (const [k, v] of Object.entries(values && typeof values === 'object' ? values : {})) if (/^[A-Za-z_]\w*$/.test(k) && (v === null || ['string', 'number', 'boolean'].includes(typeof v))) next[k] = v;
  GLOBALS = next;
  GLOBALS_VERSION += 1;
};
export const getRuleGlobals = () => GLOBALS;
export const ruleGlobalsVersion = () => GLOBALS_VERSION;
// the words of the built-in global variables (what the builder suggests before the person's own values are known)
export const BUILTIN_GLOBALS = ['fullName', 'username', 'email', 'mobile', 'employeeCode', 'category', 'affiliate', 'branch', 'department', 'designation', 'reportingManager', 'city', 'country', 'pin'];

const NO = new Set(['false', 'f', '0', 'no', 'n']);
const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

// what the parser answered -> true (valid), false (not valid) or null (the expression could not be read: the parser answers '' for that)
export function ruleResult(v) {
  if (v === true) return true;
  if (v === false) return false;
  if (typeof v === 'number') return v !== 0 && !Number.isNaN(v);
  if (typeof v === 'string') {
    const t = v.trim().toLowerCase();
    if (t === '') return null;
    return !NO.has(t);
  }
  return null;
}

// how the parser wants a value: dates as dd/mm/yyyy (our date fields hold yyyy-mm-dd), lists as comma text, places and payments left out
const forParser = (v) => {
  if (v === undefined || v === null) return '';
  if (Array.isArray(v)) return v.join(',');
  if (typeof v === 'object') return '';
  if (typeof v === 'string') { const m = ISO_DATE.exec(v); if (m) return `${m[3]}/${m[2]}/${m[1]}`; }
  return v;
};

// Is the rule met? true / false, or null when there is nothing to check or the expression can't be read (never block a person over a broken rule).
export function evaluateRule(expr, values) {
  const out = evaluateExpression(expr, values);
  return out === null ? null : ruleResult(out);
}

// What the parser answers for an expression over the form's values, as it is (a number, text, true / false), or null when there is nothing to evaluate or it
// could not be run. Rules read it as true / false (above); an auto value (fieldCalc.js) takes it as the value.
export function evaluateExpression(expr, values) {
  const text = String(expr ?? '').trim();
  if (!text) return null;
  let arr = [];
  const put = (n, v, rno) => { if (n && !n.includes('__') && /^[A-Za-z_][\w]*$/.test(n)) arr = RegisterVariable(arr, { n, v: forParser(v), rno }); };
  for (const [n, v] of Object.entries(GLOBALS)) { put(n, v, 1); put(`${GLOBAL_PREFIX}${n}`, v, 1); put(`${LEGACY_GLOBAL_PREFIX}${n}`, v, 1); }   // login_<name> is the signed-in person's (login_employeeCode), always; the plain name still works (under the form's own fields: a field named like it wins)
  for (const [n, v] of Object.entries(values || {})) {
    // the rows of a grid section: each cell is registered on its own row number (1, 2, ...) so Total(qty), GetRowCount(qty) and the like work on ordinary fields
    if (Array.isArray(v) && v.length && v.every((r) => r && typeof r === 'object' && !Array.isArray(r))) {
      v.forEach((row, i) => Object.entries(row).forEach(([k, x]) => put(k, x, i + 1)));
    } else put(n, v, 1);
  }
  try {
    return Evaluate(text, '__rule', 1, { reactFieldArray: arr });
  } catch {
    return null;
  }
}

// A field that has no value yet (nothing typed, nothing fetched) is not in the form's values at all, and the parser cannot read a rule that names a variable it does
// was never given: it answers nothing, and the rule is skipped (a person is never blocked over a rule that cannot be read). So before a rule is checked every field of
// the form is given, blank when it has no value: `lastPunchOut=""` and Val(lastPunchOut)>=Val(lastPunchIn) then mean what they say.
export const withBlanks = (ids, values) => {
  const out = { ...(values || {}) };
  for (const id of ids || []) if (id && out[id] === undefined) out[id] = '';
  return out;
};

// The message to show for one field, or null. A field left empty is not checked (required handles that), like every other check.
export function fieldRuleError(field, value, values) {
  const rule = field?.rule;
  if (!rule || !String(rule.expr ?? '').trim()) return null;
  if (value === undefined || value === null || value === '' || (Array.isArray(value) && value.length === 0)) return null;
  const id = field.id ?? field.name;
  const ok = evaluateRule(rule.expr, { ...(values || {}), [id]: value });
  if (ok !== false) return null;
  return String(rule.message ?? '').trim() || `${field.label || field.caption || id} is not valid`;
}
