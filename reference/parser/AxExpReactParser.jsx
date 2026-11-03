const RegVarFldList = [];
export let dateFormat = 'dd/mm/yyyy';

export function RegisterVariable(reactFieldArray, variable) {
  if (!Array.isArray(reactFieldArray) || !variable || typeof variable !== 'object') {
    throw new TypeError('reactFieldArray and variable must be an array and an object');
  }

  const { n, v, rno } = variable;
  if (!String(n ?? '').trim() || rno === undefined) {
    throw new TypeError('Each variable must have a name and row number');
  }

  const normalizedVariable = { n: String(n).trim().toLowerCase(), v, rno: String(rno) };
  const existingIndex = reactFieldArray.findIndex(entry =>
    entry.n.toLowerCase() === normalizedVariable.n.toLowerCase() &&
    String(entry.rno) === normalizedVariable.rno
  );

  if (existingIndex === -1) return [...reactFieldArray, normalizedVariable];
  return reactFieldArray.map((entry, index) =>
    index === existingIndex ? normalizedVariable : entry
  );
}

export function GetValue(reactFieldArray, varName, rowNo) {
  return reactFieldArray.find(
    entry => String(entry.n ?? '').trim().toLowerCase() === String(varName ?? '').trim().toLowerCase() &&
      String(entry.rno) === String(rowNo)
  )?.v;
}

export function Evaluate(expression, varName, rowNo, context = {}) {
  if (!String(expression ?? '').trim()) return '';
  const {
    reactFieldArray = []
  } = context;
  const targetFieldName = String(varName ?? '').toLowerCase();
  const targetField = reactFieldArray.find(entry =>
    entry.n.toLowerCase() === targetFieldName &&
    (rowNo == null || Number(entry.rno) === Number(rowNo))
  );
  const evaluationRowNo = Number(rowNo ?? targetField?.rowNo ?? 1);

  function resolveVariable(variableName) {
    if (variableName.toLowerCase() === 'activerow') return evaluationRowNo;

    const fieldEntry = reactFieldArray.find(entry =>
      entry.n.toLowerCase() === variableName.toLowerCase() &&
      Number(entry.rno) === evaluationRowNo
    );
    if (fieldEntry) return normalizeValue(fieldEntry.v);

    const registeredValue = findVariable(RegVarFldList, ':', variableName, true);
    if (registeredValue !== undefined) return registeredValue;
    return undefined;
  }

  try {
    const result = calculate(
      String(expression).replace(/♦/g, ','),
      resolveVariable,
      reactFieldArray,
      evaluationRowNo,
      context
    );
    return typeof result === 'number' && !Number.isFinite(result) ? 0 : result;
  } catch {
    return '';
  }
}

export function SetDateFormat(format) {
  const normalizedFormat = String(format ?? '').trim().toLowerCase();
  if (!['dd/mm/yyyy', 'mm/dd/yyyy'].includes(normalizedFormat)) {
    throw new RangeError('dateFormat must be dd/mm/yyyy or mm/dd/yyyy');
  }

  dateFormat = normalizedFormat;
}

function normalizeValue(value, parseTypedValue = false) {
  if (typeof value === 'number') return value;
  if (value == null) return '';

  const text = String(value).trim();
  if (text === '') return 0;

  if (parseTypedValue) {
    const typedValue = text.match(/^([nsd]):([\s\S]*)$/) || text.match(/^([nsd])(?=[+-]?(?:\d|\.))([\s\S]*)$/);
    if (typedValue) {
      if (typedValue[1] === 'n') return normalizeValue(typedValue[2]);
      return typedValue[2];
    }
  }

  return /^[-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?$/i.test(text)
    ? Number(text)
    : text;
}

function findVariable(list, separator, variableName, parseTypedValue = false) {
  for (const item of list) {
    let name;
    let value;

    if (typeof item === 'string') {
      const separatorIndex = item.indexOf(separator);
      if (separatorIndex === -1) continue;
      name = item.slice(0, separatorIndex).trim();
      value = item.slice(separatorIndex + 1);
    } else if (item && typeof item === 'object') {
      name = item.n ?? item.name ?? item.variableName ?? item.fieldName;
      value = item.v ?? item.value ?? item.fieldValue;
    }

    if (String(name ?? '').toLowerCase() === variableName.toLowerCase()) {
      return normalizeValue(value, parseTypedValue);
    }
  }

  return undefined;
}

function tokenize(expression) {
  const tokens = [];
  let position = 0;

  while (position < expression.length) {
    if (/\s/.test(expression[position])) {
      position++;
      continue;
    }

    const remaining = expression.slice(position);
    const number = remaining.match(/^(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?/i);
    const identifier = remaining.match(/^[a-z_$][\w$]*/i);

    if (number) {
      tokens.push({ type: 'number', value: Number(number[0]) });
      position += number[0].length;
      continue;
    }

    if (identifier) {
      tokens.push({ type: 'identifier', value: identifier[0] });
      position += identifier[0].length;
      continue;
    }

    if (expression[position] === '"' || expression[position] === "'") {
      const quote = expression[position++];
      let value = '';
      let closed = false;

      while (position < expression.length) {
        const character = expression[position++];
        if (character === quote) {
          closed = true;
          break;
        }
        if (character === '\\' && position < expression.length) {
          const escaped = expression[position++];
          value += ({ n: '\n', r: '\r', t: '\t' })[escaped] ?? escaped;
        } else {
          value += character;
        }
      }

      if (!closed) throw new Error('Unclosed string');
      tokens.push({ type: 'string', value });
      continue;
    }

    if (expression[position] === '{') {
      const end = expression.indexOf('}', position + 1);
      if (end === -1) throw new Error('Unclosed constant');
      tokens.push({ type: 'string', value: expression.slice(position + 1, end) });
      position = end + 1;
      continue;
    }

    const operator = remaining.match(/^(?:&&|\|\||==|!=|<=|>=|[+\-*/%^()=<>#&,|])/);
    if (operator) {
      tokens.push({ type: operator[0], value: operator[0] });
      position += operator[0].length;
      continue;
    }

    throw new Error(`Unsupported character: ${expression[position]}`);
  }

  return tokens;
}

function parseFormulaDate(value, dateFormat = 'dd/mm/yyyy') {
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value;

  const text = String(value ?? '').trim();
  let year;
  let month;
  let day;
  const isoDate = text.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);

  if (isoDate) {
    [, year, month, day] = isoDate;
  } else {
    const parts = text.split(/[/.\-]/);
    if (parts.length !== 3) return null;
    const isMonthFirst = String(dateFormat).toLowerCase().startsWith('mm');
    [month, day, year] = isMonthFirst ? parts : [parts[1], parts[0], parts[2]];
  }

  year = Number(year);
  month = Number(month);
  day = Number(day);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  return parsed.getUTCFullYear() === year &&
    parsed.getUTCMonth() === month - 1 &&
    parsed.getUTCDate() === day
    ? parsed
    : null;
}

function formatFormulaDate(date, dateFormat = 'dd/mm/yyyy') {
  const day = String(date.getUTCDate()).padStart(2, '0');
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const year = String(date.getUTCFullYear()).padStart(4, '0');
  return String(dateFormat).toLowerCase().startsWith('mm')
    ? `${month}/${day}/${year}`
    : `${day}/${month}/${year}`;
}

function addMonthsClamped(date, months) {
  const result = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));
  result.setUTCMonth(result.getUTCMonth() + months);
  result.setUTCDate(Math.min(date.getUTCDate(), new Date(Date.UTC(
    result.getUTCFullYear(), result.getUTCMonth() + 1, 0
  )).getUTCDate()));
  return result;
}

function wordsUnderThousand(value) {
  const units = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine'];
  const teens = ['Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
  const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
  const words = [];
  let remaining = value;

  if (remaining >= 100) {
    words.push(`${units[Math.floor(remaining / 100)]} Hundred`);
    remaining %= 100;
  }
  if (remaining >= 20) {
    words.push(tens[Math.floor(remaining / 10)]);
    remaining %= 10;
  } else if (remaining >= 10) {
    words.push(teens[remaining - 10]);
    remaining = 0;
  }
  if (remaining > 0) words.push(units[remaining]);
  return words.join(' ');
}

function amountInWords(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return '';
  if (number === 0) return 'Zero';

  const scales = ['', 'Thousand', 'Lakh', 'Crore', 'Arab', 'Kharab'];
  let whole = Math.floor(Math.abs(number));
  const groups = [whole % 1000];
  whole = Math.floor(whole / 1000);
  while (whole > 0) {
    groups.push(whole % 100);
    whole = Math.floor(whole / 100);
  }

  const parts = groups.map((group, index) => {
    const words = wordsUnderThousand(group);
    return words && scales[index] ? `${words} ${scales[index]}` : words;
  }).filter(Boolean).reverse();

  return `${number < 0 ? 'Minus ' : ''}${parts.join(' ')}`;
}

function formatFormulaAmount(value, decimals = 2, useCommas = true) {
  const number = Number(value);
  if (!Number.isFinite(number)) return '0.00';
  const places = Math.max(0, Math.min(12, Number(decimals) || 0));
  return new Intl.NumberFormat(useCommas ? 'en-IN' : 'en-US', {
    useGrouping: Boolean(useCommas),
    minimumFractionDigits: places,
    maximumFractionDigits: places
  }).format(number);
}

function encodeBase64(value) {
  const bytes = new TextEncoder().encode(String(value ?? ''));
  const binary = Array.from(bytes, byte => String.fromCharCode(byte)).join('');
  return btoa(binary);
}

function decodeBase64(value) {
  const binary = atob(String(value ?? ''));
  const bytes = Uint8Array.from(binary, character => character.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

function md5(value) {
  const bytes = Array.from(new TextEncoder().encode(String(value ?? '')));
  const bitLength = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  for (let index = 0; index < 8; index++) {
    bytes.push(Math.floor(bitLength / (2 ** (8 * index))) & 0xff);
  }

  const shifts = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
  ];
  const constants = Array.from({ length: 64 }, (_, index) =>
    Math.floor(Math.abs(Math.sin(index + 1)) * 0x100000000) >>> 0
  );
  let a0 = 0x67452301;
  let b0 = 0xefcdab89;
  let c0 = 0x98badcfe;
  let d0 = 0x10325476;

  for (let offset = 0; offset < bytes.length; offset += 64) {
    const words = Array.from({ length: 16 }, (_, index) => {
      const position = offset + index * 4;
      return (bytes[position] | (bytes[position + 1] << 8) |
        (bytes[position + 2] << 16) | (bytes[position + 3] << 24)) >>> 0;
    });
    let a = a0;
    let b = b0;
    let c = c0;
    let d = d0;

    for (let index = 0; index < 64; index++) {
      let mix;
      let wordIndex;
      if (index < 16) {
        mix = (b & c) | (~b & d);
        wordIndex = index;
      } else if (index < 32) {
        mix = (d & b) | (~d & c);
        wordIndex = (5 * index + 1) % 16;
      } else if (index < 48) {
        mix = b ^ c ^ d;
        wordIndex = (3 * index + 5) % 16;
      } else {
        mix = c ^ (b | ~d);
        wordIndex = (7 * index) % 16;
      }

      const sum = (a + mix + constants[index] + words[wordIndex]) >>> 0;
      const rotated = (sum << shifts[index]) | (sum >>> (32 - shifts[index]));
      [a, d, c, b] = [d, c, b, (b + rotated) >>> 0];
    }

    a0 = (a0 + a) >>> 0;
    b0 = (b0 + b) >>> 0;
    c0 = (c0 + c) >>> 0;
    d0 = (d0 + d) >>> 0;
  }

  return [a0, b0, c0, d0].map(word =>
    [0, 8, 16, 24].map(shift => ((word >>> shift) & 0xff).toString(16).padStart(2, '0')).join('')
  ).join('');
}

function infixToPostfix(expression) {
  const output = [];
  const operators = [];
  const precedence = { '|': 1, '&': 2, '+': 3, '-': 3, '*': 4, '/': 4, '^': 5 };

  for (const token of tokenize(expression)) {
    if (token.type === 'number' || token.type === 'identifier' || token.type === 'string') {
      output.push(token.type === 'string' ? JSON.stringify(token.value) : String(token.value));
    } else if (token.type === '(') {
      operators.push('(');
    } else if (token.type === ')') {
      while (operators.length && operators.at(-1) !== '(') output.push(operators.pop());
      if (operators.pop() !== '(') throw new Error('Mismatched parentheses');
    } else {
      while (operators.length && operators.at(-1) !== '(' &&
        (precedence[operators.at(-1)] > precedence[token.type] ||
          (precedence[operators.at(-1)] === precedence[token.type] && token.type !== '^'))) {
        output.push(operators.pop());
      }
      operators.push(token.type);
    }
  }

  while (operators.length) {
    const operator = operators.pop();
    if (operator === '(') throw new Error('Mismatched parentheses');
    output.push(operator);
  }
  return output.join(' ');
}

function postfixToInfix(expression) {
  const tokens = String(expression).trim().split(/\s+/);
  const stack = [];
  for (const token of tokens) {
    if (/^[+\-*/^]$/.test(token)) {
      const right = stack.pop();
      const left = stack.pop();
      if (left === undefined || right === undefined) throw new Error('Invalid postfix expression');
      stack.push(`(${left}${token}${right})`);
    } else {
      stack.push(token);
    }
  }
  if (stack.length !== 1) throw new Error('Invalid postfix expression');
  return stack[0];
}

function evaluatePostfix(expression) {
  const tokens = String(expression).trim().includes(' ')
    ? String(expression).trim().split(/\s+/)
    : String(expression).split('');
  const stack = [];
  for (const token of tokens) {
    if (/^[+\-*/^]$/.test(token)) {
      const right = Number(stack.pop());
      const left = Number(stack.pop());
      if (!Number.isFinite(left) || !Number.isFinite(right)) throw new Error('Invalid postfix expression');
      if (token === '+') stack.push(left + right);
      if (token === '-') stack.push(left - right);
      if (token === '*') stack.push(left * right);
      if (token === '/') stack.push(left / right);
      if (token === '^') stack.push(left ** right);
    } else {
      const number = Number(token);
      if (!Number.isFinite(number)) throw new Error('Postfix evaluation supports numeric operands only');
      stack.push(number);
    }
  }
  if (stack.length !== 1) throw new Error('Invalid postfix expression');
  return stack[0];
}

function RegisterRegVars(varName, varType, varValue) {
  const name = String(varName ?? '').trim();
  if (!name) return '';

  const entry = `${name}:${varType ?? ''}:${varValue ?? ''}`;
  const existingIndex = RegVarFldList.findIndex(value =>
    value.slice(0, value.indexOf(':')).toLowerCase() === name.toLowerCase()
  );

  if (existingIndex === -1) RegVarFldList.push(entry);
  else RegVarFldList[existingIndex] = entry;

  return '';
}

function evaluateFunction(name, args, reactFieldArray, rowNo, context) {
  const [first, second, third] = args;
  const text = value => String(value ?? '');
  const numeric = value => Number(value);
  const activeDateFormat = context.dateFormat ?? dateFormat;
  const asBoolean = value => typeof value === 'string'
    ? !['', '0', 'f', 'false', 'n', 'no'].includes(value.trim().toLowerCase())
    : Boolean(value);

  function matchingFields(fieldName) {
    return reactFieldArray
      .filter(field => field.n.toLowerCase() === text(fieldName).toLowerCase())
      .sort((left, right) => Number(left.rno) - Number(right.rno));
  }

  function rowExtreme(fieldName, isMinimum) {
    const values = matchingFields(fieldName)
      .map((field, index) => ({ index, value: Number(normalizeValue(field.v)) }))
      .filter(entry => Number.isFinite(entry.value));
    if (!values.length) return 0;
    const extreme = values.reduce((best, entry) =>
      isMinimum ? Math.min(best, entry.value) : Math.max(best, entry.value),
    values[0].value);
    return values.find(entry => entry.value === extreme).index + 1;
  }

  function dateArgument(value) {
    const date = parseFormulaDate(value, activeDateFormat);
    if (!date) throw new Error('Invalid date');
    return date;
  }

  switch (name.toLowerCase()) {
    case 'regvar':
      return RegisterRegVars(text(first), text(second), third);
    case 'abs': return Math.abs(numeric(first));
    case 'ceil':
    case 'axpceil': return Math.ceil(numeric(first));
    case 'floor':
    case 'axpfloor': return Math.floor(numeric(first));
    case 'round': return Math.round(numeric(first));
    case 'roundoff': {
      const places = Math.max(0, Math.min(12, numeric(second) || 0));
      const factor = 10 ** places;
      return Math.round((numeric(first) + Number.EPSILON) * factor) / factor;
    }
    case 'evaluatepower': return numeric(first) ** numeric(second);
    case 'getinteger': return Number.parseInt(first, 10) || 0;
    case 'length':
    case 'getlength': return text(first).length;
    case 'substr': {
      const start = Math.max(0, (numeric(second) || 1) - 1);
      const end = args.length > 2 ? start + Math.max(0, numeric(third)) : undefined;
      return text(first).substring(start, end);
    }
    case 'upper':
    case 'uppercase': return text(first).toUpperCase();
    case 'lower':
    case 'lowercase': return text(first).toLowerCase();
    case 'trim':
    case 'trimall': return text(first).trim();
    case 'triminbetwnspaces': return text(first).replace(/\s/g, '');
    case 'isempty':
    case 'isemptyvalue':
    case 'isvarempty': return text(first) === '' ? 'T' : 'F';
    case 'iif': return first ? second : third;
    case 'val': return Number.parseFloat(text(first).replace(/,/g, '')) || 0;
    case 'str':
    case 'getvarvalue': return text(first);
    case 'mods':
    case 'getmod': return numeric(second) === 0 ? 0 : numeric(first) % numeric(second);
    case 'extractnum': return text(first).replace(/\D/g, '');
    case 'removecommas': return text(first).replace(/,/g, '') || '0';
    case 'findcharpos': return text(first).indexOf(text(second));
    case 'findandreplace': {
      const search = text(second).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      return text(first).replace(new RegExp(search, 'gi'), text(third));
    }
    case 'chkuniqchar': return new Set(text(first)).size !== text(first).length;
    case 'getnthstring': return text(first).substring(Math.max(0, numeric(second) || 0));
    case 'getseperatorcount': {
      const separator = text(second);
      return separator ? text(first).split(separator).length - 1 : 0;
    }
    case 'leftpad': return text(first).padStart(numeric(second), text(third) || '0');
    case 'rightpad': return text(first).padEnd(numeric(second), text(third) || '0');
    case 'pad': {
      const targetLength = Math.max(0, numeric(second));
      const character = text(third) || '0';
      let result = text(first);
      while (result.length < targetLength) {
        result = character + result;
        if (result.length < targetLength) result += character;
      }
      return result;
    }
    case 'formatval': {
      const places = Math.max(0, Math.min(12, numeric(second) || 2));
      return Number(numeric(first).toFixed(places));
    }
    case 'lastdayofmonth': {
      const date = dateArgument(first);
      return formatFormulaDate(new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)), activeDateFormat);
    }
    case 'daysinmonth': {
      const date = second === undefined ? parseFormulaDate(first, activeDateFormat) : null;
      const year = date ? date.getUTCFullYear() : numeric(first);
      const month = date ? date.getUTCMonth() + 1 : numeric(second);
      return new Date(Date.UTC(year, month, 0)).getUTCDate();
    }
    case 'validencodedate': {
      const date = new Date(Date.UTC(numeric(first), numeric(second) - 1, numeric(third)));
      return formatFormulaDate(date, activeDateFormat);
    }
    case 'addtomonth': {
      return formatFormulaDate(addMonthsClamped(dateArgument(first), numeric(second)), activeDateFormat);
    }
    case 'addtodate': {
      const date = dateArgument(first);
      date.setUTCDate(date.getUTCDate() + numeric(second));
      return formatFormulaDate(date, activeDateFormat);
    }
    case 'timeelapsed': {
      const milliseconds = Math.abs(dateArgument(second) - dateArgument(first));
      const totalSeconds = Math.floor(milliseconds / 1000);
      const days = Math.floor(totalSeconds / 86400);
      const hours = Math.floor((totalSeconds % 86400) / 3600);
      const minutes = Math.floor((totalSeconds % 3600) / 60);
      const seconds = totalSeconds % 60;
      return `${days} days, ${hours} hours, ${minutes} minutes, ${seconds} seconds`;
    }
    case 'dayselapsed':
    case 'datediff':
      return Math.floor(Math.abs(dateArgument(second) - dateArgument(first)) / 86400000);
    case 'mandy': {
      const date = dateArgument(first);
      return `${date.getUTCFullYear()}${String(date.getUTCMonth() + 1).padStart(2, '0')}`;
    }
    case 'insertcommas': return formatFormulaAmount(first, 2, true);
    case 'amtword': return `Rupees ${amountInWords(first)} Only`;
    case 'curramtword': {
      const amountParts = text(first).split('.');
      const wholeWords = amountInWords(amountParts[0]);
      const decimalDigits = amountParts[1] ?? '';
      const decimalWords = decimalDigits ? amountInWords(decimalDigits) : '';
      const major = `${text(second)}${wholeWords}`;
      return decimalWords
        ? `${major} and ${text(third)} ${decimalWords} only`
        : `${major} only`;
    }
    case 'infixtopostfix': return infixToPostfix(first);
    case 'postfixtoinfix': return postfixToInfix(first);
    case 'postfixeval': return evaluatePostfix(first);
    case 'inputprecedence': {
      return ({ ')': 0, '|': 1, '&': 3, '+': 5, '-': 5, '*': 7, '/': 7, '^': 10, '>': 10, '<': 10, '=': 10, '#': 10, '$': 10, '(': 13 })[text(first)] ?? 11;
    }
    case 'stackprecedence': {
      return ({ '(': 0, '|': 2, '&': 4, '+': 6, '-': 6, '*': 8, '/': 8, '^': 9, '>': 9, '<': 9, '=': 9, '#': 9, '$': 9 })[text(first)] ?? 12;
    }
    case 'isoperator': return /^[+\-*/^=<>#&|$]$/.test(text(first));
    case 'encode': return encodeBase64(first);
    case 'decode': return decodeBase64(first);
    case 'dtoc':
    case 'ctod': return formatFormulaDate(dateArgument(first), activeDateFormat);
    case 'cmonthyear': {
      const date = dateArgument(first);
      return `${date.toLocaleString('en', { month: 'long', timeZone: 'UTC' })} ${date.getUTCFullYear()}`;
    }
    case 'stuff': {
      const source = text(first);
      const position = Math.max(0, Math.min(source.length, numeric(third)));
      return source.slice(0, position) + text(second) + source.slice(position);
    }
    case 'rnd': {
      const step = numeric(second);
      if (!step) return 0;
      return Math.round(numeric(first) * 100 / step) * step / 100;
    }
    case 'formatamount': {
      const amount = numeric(first);
      const shouldGroup = String(args[2] ?? '').toLowerCase() === 't' ||
        ['true', 't'].includes(String(args[3] ?? '').toLowerCase());
      const places = numeric(second) || 2;
      const formatted = formatFormulaAmount(Math.abs(amount), places, shouldGroup);
      const negativeRep = text(args[4]);
      const positiveRep = text(args[5]);
      if ((negativeRep === 'br' || positiveRep === 'br') && amount < 0) return `(${formatted})`;
      const suffix = amount < 0 ? negativeRep : positiveRep;
      return `${formatted}${suffix && suffix !== 'br' ? ` ${suffix}` : ''}`;
    }
    case 'formataccamount': {
      const amount = numeric(first);
      const formatted = formatFormulaAmount(Math.abs(amount), numeric(second) || 2,
        ['true', 't'].includes(String(third).toLowerCase()));
      const signMode = text(args[3]).toLowerCase();
      const currency = text(args[4]);
      if (currency.toLowerCase() === 'br' && ((signMode === 'a' || signMode === 'e') ? amount < 0 : amount > 0)) {
        return `(${formatted})`;
      }
      return currency ? `${formatted} ${currency}` : formatted;
    }
    case 'date': return formatFormulaDate(new Date(), activeDateFormat);
    case 'time': return new Date().toTimeString().slice(0, 8);
    case 'checkemail': return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(text(first));
    case 'convertmd5': return md5(first);
    case 'makedate': {
      const date = new Date(Date.UTC(numeric(third), numeric(second) - 1, numeric(first)));
      return formatFormulaDate(date, activeDateFormat);
    }
    case 'dayofdate': return dateArgument(first).getUTCDate();
    case 'monthofdate': return dateArgument(first).getUTCMonth() + 1;
    case 'yearofdate': return dateArgument(first).getUTCFullYear();
    case 'getmin': return rowExtreme(first, true);
    case 'getmax': return rowExtreme(first, false);
    case 'networkdays': {
      const startDate = dateArgument(first);
      const endDate = dateArgument(second);
      if (startDate > endDate) return -1;
      let weekdays = 0;
      for (let date = startDate; date <= endDate; date.setUTCDate(date.getUTCDate() + 1)) {
        const day = date.getUTCDay();
        if (day !== 0 && day !== 6) weekdays++;
      }
      return weekdays - (numeric(third) || 0);
    }
    case 'days360': {
      const start = dateArgument(first);
      const end = dateArgument(second);
      const method = asBoolean(third);
      let startDay = start.getUTCDate();
      let endDay = end.getUTCDate();
      if (method) {
        if (startDay === 31) startDay = 30;
        if (endDay === 31) endDay = 30;
      } else {
        const lastStartDay = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + 1, 0)).getUTCDate();
        const lastEndDay = new Date(Date.UTC(end.getUTCFullYear(), end.getUTCMonth() + 1, 0)).getUTCDate();
        if (startDay === lastStartDay) startDay = 30;
        if (endDay === lastEndDay && startDay < 30) endDay = 30;
      }
      return ((end.getUTCFullYear() - start.getUTCFullYear()) * 12 + end.getUTCMonth() - start.getUTCMonth()) * 30 + endDay - startDay;
    }
    case 'getvalue': {
      const requestedRow = args.length > 1 ? Number(second) : Number(rowNo);
      const entry = reactFieldArray.find(field =>
        field.n.toLowerCase() === text(first).toLowerCase() &&
        Number(field.rno) === requestedRow
      );
      return entry ? normalizeValue(entry.v) : '';
    }
    case 'total': {
      return reactFieldArray
        .filter(field => field.n.toLowerCase() === text(first).toLowerCase())
        .reduce((sum, field) => sum + (Number(normalizeValue(field.v)) || 0), 0);
    }
    case 'getrowcount': {
      return new Set(matchingFields(first).map(field => field.rno)).size;
    }
    case 'stringpos': {
      const separator = third === undefined || third === '' ? ',' : text(third);
      return text(second).split(separator).indexOf(text(first));
    }
    case 'getrow': {
      const match = reactFieldArray.find(field =>
        field.n.toLowerCase() === text(first).toLowerCase() &&
        String(field.v) === String(second)
      );
      return match ? Number(match.rno) : -1;
    }
    case 'sum':
    case 'sumtill': {
      const limit = name.toLowerCase() === 'sumtill' && args.length > 3
        ? Number(args[3])
        : Infinity;
      const matchingRows = new Set(reactFieldArray
        .filter(field => field.n.toLowerCase() === text(first).toLowerCase() &&
          String(field.v) === String(second) && Number(field.rno) <= limit)
        .map(field => Number(field.rno)));
      return reactFieldArray
        .filter(field => field.n.toLowerCase() === text(third).toLowerCase() &&
          matchingRows.has(Number(field.rno)))
        .reduce((sum, field) => sum + (Number(normalizeValue(field.v)) || 0), 0);
    }
    case 'getallvalues': {
      return matchingFields(first).map(field => String(field.v ?? '')).filter(Boolean).join(',');
    }
    default: throw new Error(`Unsupported function: ${name}`);
  }
}

function calculate(expression, resolveVariable, reactFieldArray, rowNo, context = {}) {
  const tokens = tokenize(expression);
  let position = 0;

  function parsePrimary() {
    const token = tokens[position++];

    if (!token) throw new Error('Expected a value');
    if (token.type === 'number') return token.value;
    if (token.type === 'string') return token.value;
    if (token.type === 'identifier') {
      if (tokens[position]?.type === '(') {
        position++;
        const args = [];
        if (tokens[position]?.type !== ')') {
          do {
            if (token.value.toLowerCase() === 'total' && args.length === 0 &&
              tokens[position]?.type === 'identifier' && tokens[position + 1]?.type !== '(') {
              args.push(tokens[position++].value);
            } else {
              args.push(parseOr());
            }
            if (tokens[position]?.type !== ',') break;
            position++;
          } while (position < tokens.length);
        }
        if (tokens[position++]?.type !== ')') throw new Error('Expected closing parenthesis');
        return evaluateFunction(token.value, args, reactFieldArray, rowNo, context);
      }

      const value = resolveVariable(token.value);
      if (value === undefined) throw new Error(`Unknown variable: ${token.value}`);
      return value;
    }
    if (token.type === '(') {
      const value = parseOr();
      if (tokens[position++]?.type !== ')') throw new Error('Expected closing parenthesis');
      return value;
    }

    throw new Error('Expected a number, variable, or parenthesized expression');
  }

  function parsePower() {
    const left = parsePrimary();
    if (tokens[position]?.type === '^') {
      position++;
      return Number(left) ** Number(parseUnary());
    }
    return left;
  }

  function parseUnary() {
    const operator = tokens[position]?.type;
    if (operator === '+' || operator === '-') {
      position++;
      const value = Number(parseUnary());
      return operator === '-' ? -value : value;
    }
    return parsePower();
  }

  function parseMultiplicative() {
    let value = parseUnary();

    while (['*', '/', '%'].includes(tokens[position]?.type)) {
      const operator = tokens[position++].type;
      const right = Number(parseUnary());
      const left = Number(value);
      if (operator === '*') value = left * right;
      if (operator === '/') value = left / right;
      if (operator === '%') value = left % right;
    }

    return value;
  }

  function parseAdditive() {
    let value = parseMultiplicative();

    while (['+', '-'].includes(tokens[position]?.type)) {
      const operator = tokens[position++].type;
      const right = parseMultiplicative();
      value = operator === '+'
        ? value + right
        : Number(value) - Number(right);
    }

    return value;
  }

  function parseComparison() {
    let value = parseAdditive();

    while (['=', '==', '!=', '#', '<', '>', '<=', '>='].includes(tokens[position]?.type)) {
      const operator = tokens[position++].type;
      const right = parseAdditive();
      if (operator === '=' || operator === '==') value = value == right;
      if (operator === '!=' || operator === '#') value = value != right;
      if (operator === '<') value = value < right;
      if (operator === '>') value = value > right;
      if (operator === '<=') value = value <= right;
      if (operator === '>=') value = value >= right;
    }

    return value;
  }

  function parseAnd() {
    let value = parseComparison();
    while (['&', '&&'].includes(tokens[position]?.type)) {
      position++;
      const right = parseComparison();
      value = Boolean(value) && Boolean(right);
    }
    return value;
  }

  function parseOr() {
    let value = parseAnd();
    while (['|', '||'].includes(tokens[position]?.type)) {
      position++;
      const right = parseAnd();
      value = Boolean(value) || Boolean(right);
    }
    return value;
  }

  const result = parseOr();
  if (position !== tokens.length) throw new Error('Unexpected token');
  return result;
}
