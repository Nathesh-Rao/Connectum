// Whether a field or section is shown: the "condition" of a form field (docs/FORM_LOGIC_FOR_MOBILE.md). One function for the web app and for the mobile app (it is in the published
// form logic, with cases in form-logic-conformance.json), so a condition is met in exactly the same cases everywhere. The server has the final say (sd_config_values.erl).
//
// cond: nothing (always met) | { all: [cond...] } (every one) | { any: [cond...] } (at least one) | { field, op, value }
// ops: eq ne gt lt gte lte in between notempty. `values` is { fieldName: value }.
// Text is compared exactly as it is: capitals count and nothing is trimmed. Two numbers (or text that is a number) compare as numbers, anything else as text.

/** Nothing there: not set, null, "" or an empty list. Text of spaces is NOT empty. */
export const isEmpty = (v) => v === undefined || v === null || v === '' || (Array.isArray(v) && v.length === 0);

const toNum = (v) => {
  if (typeof v === 'number') return v;
  if (typeof v === 'string' && v.trim() !== '' && !Number.isNaN(Number(v))) return Number(v);
  return null;
};

// Numbers compare numerically when both sides are numbers, otherwise as text (same as the server).
function cmp(a, b) {
  const x = toNum(a);
  const y = toNum(b);
  if (x !== null && y !== null) return x < y ? -1 : x > y ? 1 : 0;
  const sa = String(a ?? '');
  const sb = String(b ?? '');
  return sa < sb ? -1 : sa > sb ? 1 : 0;
}

export function evalCondition(cond, values) {
  if (!cond) return true;
  if (Array.isArray(cond.all)) return cond.all.every((c) => evalCondition(c, values));
  if (Array.isArray(cond.any)) return cond.any.some((c) => evalCondition(c, values));
  const v = values[cond.field];
  switch (cond.op) {
    case 'eq':
      return Array.isArray(v) ? v.includes(cond.value) : cmp(v, cond.value) === 0 && !isEmpty(v);
    case 'ne':
      return Array.isArray(v) ? !v.includes(cond.value) : cmp(v, cond.value) !== 0;
    case 'gt':
      return !isEmpty(v) && cmp(v, cond.value) > 0;
    case 'lt':
      return !isEmpty(v) && cmp(v, cond.value) < 0;
    case 'gte':
      return !isEmpty(v) && cmp(v, cond.value) >= 0;
    case 'lte':
      return !isEmpty(v) && cmp(v, cond.value) <= 0;
    case 'in':
      return Array.isArray(cond.value) && (Array.isArray(v) ? v.some((x) => cond.value.includes(x)) : cond.value.includes(v));
    case 'between':
      return Array.isArray(cond.value) && cond.value.length === 2 && !isEmpty(v) && cmp(v, cond.value[0]) >= 0 && cmp(v, cond.value[1]) <= 0;   // from .. to, both ends included
    case 'notempty':
      return !isEmpty(v);
    default:
      return true;   // no operator (or one this version does not know): met
  }
}
