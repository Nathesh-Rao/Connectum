/* Connectum form logic: built by scripts/build-form-logic-bundle.mjs from form-studio/src/core. Load form-logic-host-shim.js first. Defines the global ConnectumFormLogic. */
"use strict";
var ConnectumFormLogic = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // form-studio/src/core/formLogicEntry.js
  var formLogicEntry_exports = {};
  __export(formLogicEntry_exports, {
    Evaluate: () => Evaluate,
    RegisterVariable: () => RegisterVariable,
    SetDateFormat: () => SetDateFormat,
    applyCalcs: () => applyCalcs,
    applyFormCalcs: () => applyFormCalcs,
    applyRowCalcs: () => applyRowCalcs,
    canCalc: () => canCalc,
    evaluateExpression: () => evaluateExpression,
    evaluateRule: () => evaluateRule,
    fieldRuleError: () => fieldRuleError,
    fitCalc: () => fitCalc,
    hasCalc: () => hasCalc,
    ruleResult: () => ruleResult,
    runConformance: () => runConformance,
    setRuleGlobals: () => setRuleGlobals,
    usedFields: () => usedFields,
    withBlanks: () => withBlanks
  });

  // form-studio/src/core/axExpParser.js
  var RegVarFldList = [];
  var dateFormat = "dd/mm/yyyy";
  function RegisterVariable(reactFieldArray, variable) {
    if (!Array.isArray(reactFieldArray) || !variable || typeof variable !== "object") {
      throw new TypeError("reactFieldArray and variable must be an array and an object");
    }
    const { n, v, rno } = variable;
    if (!String(n != null ? n : "").trim() || rno === void 0) {
      throw new TypeError("Each variable must have a name and row number");
    }
    const normalizedVariable = { n: String(n).trim().toLowerCase(), v, rno: String(rno) };
    const existingIndex = reactFieldArray.findIndex(
      (entry) => entry.n.toLowerCase() === normalizedVariable.n.toLowerCase() && String(entry.rno) === normalizedVariable.rno
    );
    if (existingIndex === -1) return [...reactFieldArray, normalizedVariable];
    return reactFieldArray.map(
      (entry, index) => index === existingIndex ? normalizedVariable : entry
    );
  }
  function Evaluate(expression, varName, rowNo, context = {}) {
    var _a;
    if (!String(expression != null ? expression : "").trim()) return "";
    const {
      reactFieldArray = []
    } = context;
    const targetFieldName = String(varName != null ? varName : "").toLowerCase();
    const targetField = reactFieldArray.find(
      (entry) => entry.n.toLowerCase() === targetFieldName && (rowNo == null || Number(entry.rno) === Number(rowNo))
    );
    const evaluationRowNo = Number((_a = rowNo != null ? rowNo : targetField == null ? void 0 : targetField.rowNo) != null ? _a : 1);
    function resolveVariable(variableName) {
      if (variableName.toLowerCase() === "activerow") return evaluationRowNo;
      const fieldEntry = reactFieldArray.find(
        (entry) => entry.n.toLowerCase() === variableName.toLowerCase() && Number(entry.rno) === evaluationRowNo
      );
      if (fieldEntry) return normalizeValue(fieldEntry.v);
      const registeredValue = findVariable(RegVarFldList, ":", variableName, true);
      if (registeredValue !== void 0) return registeredValue;
      return void 0;
    }
    try {
      const result = calculate(
        String(expression).replace(/♦/g, ","),
        resolveVariable,
        reactFieldArray,
        evaluationRowNo,
        context
      );
      return typeof result === "number" && !Number.isFinite(result) ? 0 : result;
    } catch {
      return "";
    }
  }
  function SetDateFormat(format) {
    const normalizedFormat = String(format != null ? format : "").trim().toLowerCase();
    if (!["dd/mm/yyyy", "mm/dd/yyyy"].includes(normalizedFormat)) {
      throw new RangeError("dateFormat must be dd/mm/yyyy or mm/dd/yyyy");
    }
    dateFormat = normalizedFormat;
  }
  function normalizeValue(value, parseTypedValue = false) {
    if (typeof value === "number") return value;
    if (value == null) return "";
    const text = String(value).trim();
    if (text === "") return 0;
    if (parseTypedValue) {
      const typedValue = text.match(/^([nsd]):([\s\S]*)$/) || text.match(/^([nsd])(?=[+-]?(?:\d|\.))([\s\S]*)$/);
      if (typedValue) {
        if (typedValue[1] === "n") return normalizeValue(typedValue[2]);
        return typedValue[2];
      }
    }
    return /^[-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?$/i.test(text) ? Number(text) : text;
  }
  function findVariable(list, separator, variableName, parseTypedValue = false) {
    var _a, _b, _c, _d, _e;
    for (const item of list) {
      let name;
      let value;
      if (typeof item === "string") {
        const separatorIndex = item.indexOf(separator);
        if (separatorIndex === -1) continue;
        name = item.slice(0, separatorIndex).trim();
        value = item.slice(separatorIndex + 1);
      } else if (item && typeof item === "object") {
        name = (_c = (_b = (_a = item.n) != null ? _a : item.name) != null ? _b : item.variableName) != null ? _c : item.fieldName;
        value = (_e = (_d = item.v) != null ? _d : item.value) != null ? _e : item.fieldValue;
      }
      if (String(name != null ? name : "").toLowerCase() === variableName.toLowerCase()) {
        return normalizeValue(value, parseTypedValue);
      }
    }
    return void 0;
  }
  function tokenize(expression) {
    var _a;
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
        tokens.push({ type: "number", value: Number(number[0]) });
        position += number[0].length;
        continue;
      }
      if (identifier) {
        tokens.push({ type: "identifier", value: identifier[0] });
        position += identifier[0].length;
        continue;
      }
      if (expression[position] === '"' || expression[position] === "'") {
        const quote = expression[position++];
        let value = "";
        let closed = false;
        while (position < expression.length) {
          const character = expression[position++];
          if (character === quote) {
            closed = true;
            break;
          }
          if (character === "\\" && position < expression.length) {
            const escaped = expression[position++];
            value += (_a = { n: "\n", r: "\r", t: "	" }[escaped]) != null ? _a : escaped;
          } else {
            value += character;
          }
        }
        if (!closed) throw new Error("Unclosed string");
        tokens.push({ type: "string", value });
        continue;
      }
      if (expression[position] === "{") {
        const end = expression.indexOf("}", position + 1);
        if (end === -1) throw new Error("Unclosed constant");
        tokens.push({ type: "string", value: expression.slice(position + 1, end) });
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
  function parseFormulaDate(value, dateFormat2 = "dd/mm/yyyy") {
    if (value instanceof Date && !Number.isNaN(value.getTime())) return value;
    const text = String(value != null ? value : "").trim();
    let year;
    let month;
    let day;
    const isoDate = text.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
    if (isoDate) {
      [, year, month, day] = isoDate;
    } else {
      const parts = text.split(/[/.\-]/);
      if (parts.length !== 3) return null;
      const isMonthFirst = String(dateFormat2).toLowerCase().startsWith("mm");
      [month, day, year] = isMonthFirst ? parts : [parts[1], parts[0], parts[2]];
    }
    year = Number(year);
    month = Number(month);
    day = Number(day);
    const parsed = new Date(Date.UTC(year, month - 1, day));
    return parsed.getUTCFullYear() === year && parsed.getUTCMonth() === month - 1 && parsed.getUTCDate() === day ? parsed : null;
  }
  function formatFormulaDate(date, dateFormat2 = "dd/mm/yyyy") {
    const day = String(date.getUTCDate()).padStart(2, "0");
    const month = String(date.getUTCMonth() + 1).padStart(2, "0");
    const year = String(date.getUTCFullYear()).padStart(4, "0");
    return String(dateFormat2).toLowerCase().startsWith("mm") ? `${month}/${day}/${year}` : `${day}/${month}/${year}`;
  }
  function addMonthsClamped(date, months) {
    const result = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));
    result.setUTCMonth(result.getUTCMonth() + months);
    result.setUTCDate(Math.min(date.getUTCDate(), new Date(Date.UTC(
      result.getUTCFullYear(),
      result.getUTCMonth() + 1,
      0
    )).getUTCDate()));
    return result;
  }
  function wordsUnderThousand(value) {
    const units = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"];
    const teens = ["Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"];
    const tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"];
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
    return words.join(" ");
  }
  function amountInWords(value) {
    const number = Number(value);
    if (!Number.isFinite(number)) return "";
    if (number === 0) return "Zero";
    const scales = ["", "Thousand", "Lakh", "Crore", "Arab", "Kharab"];
    let whole = Math.floor(Math.abs(number));
    const groups = [whole % 1e3];
    whole = Math.floor(whole / 1e3);
    while (whole > 0) {
      groups.push(whole % 100);
      whole = Math.floor(whole / 100);
    }
    const parts = groups.map((group, index) => {
      const words = wordsUnderThousand(group);
      return words && scales[index] ? `${words} ${scales[index]}` : words;
    }).filter(Boolean).reverse();
    return `${number < 0 ? "Minus " : ""}${parts.join(" ")}`;
  }
  function formatFormulaAmount(value, decimals = 2, useCommas = true) {
    const number = Number(value);
    if (!Number.isFinite(number)) return "0.00";
    const places = Math.max(0, Math.min(12, Number(decimals) || 0));
    return new Intl.NumberFormat(useCommas ? "en-IN" : "en-US", {
      useGrouping: Boolean(useCommas),
      minimumFractionDigits: places,
      maximumFractionDigits: places
    }).format(number);
  }
  function encodeBase64(value) {
    const bytes = new TextEncoder().encode(String(value != null ? value : ""));
    const binary = Array.from(bytes, (byte) => String.fromCharCode(byte)).join("");
    return btoa(binary);
  }
  function decodeBase64(value) {
    const binary = atob(String(value != null ? value : ""));
    const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    return new TextDecoder().decode(bytes);
  }
  function md5(value) {
    const bytes = Array.from(new TextEncoder().encode(String(value != null ? value : "")));
    const bitLength = bytes.length * 8;
    bytes.push(128);
    while (bytes.length % 64 !== 56) bytes.push(0);
    for (let index = 0; index < 8; index++) {
      bytes.push(Math.floor(bitLength / 2 ** (8 * index)) & 255);
    }
    const shifts = [
      7,
      12,
      17,
      22,
      7,
      12,
      17,
      22,
      7,
      12,
      17,
      22,
      7,
      12,
      17,
      22,
      5,
      9,
      14,
      20,
      5,
      9,
      14,
      20,
      5,
      9,
      14,
      20,
      5,
      9,
      14,
      20,
      4,
      11,
      16,
      23,
      4,
      11,
      16,
      23,
      4,
      11,
      16,
      23,
      4,
      11,
      16,
      23,
      6,
      10,
      15,
      21,
      6,
      10,
      15,
      21,
      6,
      10,
      15,
      21,
      6,
      10,
      15,
      21
    ];
    const constants = Array.from(
      { length: 64 },
      (_, index) => Math.floor(Math.abs(Math.sin(index + 1)) * 4294967296) >>> 0
    );
    let a0 = 1732584193;
    let b0 = 4023233417;
    let c0 = 2562383102;
    let d0 = 271733878;
    for (let offset = 0; offset < bytes.length; offset += 64) {
      const words = Array.from({ length: 16 }, (_, index) => {
        const position = offset + index * 4;
        return (bytes[position] | bytes[position + 1] << 8 | bytes[position + 2] << 16 | bytes[position + 3] << 24) >>> 0;
      });
      let a = a0;
      let b = b0;
      let c = c0;
      let d = d0;
      for (let index = 0; index < 64; index++) {
        let mix;
        let wordIndex;
        if (index < 16) {
          mix = b & c | ~b & d;
          wordIndex = index;
        } else if (index < 32) {
          mix = d & b | ~d & c;
          wordIndex = (5 * index + 1) % 16;
        } else if (index < 48) {
          mix = b ^ c ^ d;
          wordIndex = (3 * index + 5) % 16;
        } else {
          mix = c ^ (b | ~d);
          wordIndex = 7 * index % 16;
        }
        const sum = a + mix + constants[index] + words[wordIndex] >>> 0;
        const rotated = sum << shifts[index] | sum >>> 32 - shifts[index];
        [a, d, c, b] = [d, c, b, b + rotated >>> 0];
      }
      a0 = a0 + a >>> 0;
      b0 = b0 + b >>> 0;
      c0 = c0 + c >>> 0;
      d0 = d0 + d >>> 0;
    }
    return [a0, b0, c0, d0].map(
      (word) => [0, 8, 16, 24].map((shift) => (word >>> shift & 255).toString(16).padStart(2, "0")).join("")
    ).join("");
  }
  function infixToPostfix(expression) {
    const output = [];
    const operators = [];
    const precedence = { "|": 1, "&": 2, "+": 3, "-": 3, "*": 4, "/": 4, "^": 5 };
    for (const token of tokenize(expression)) {
      if (token.type === "number" || token.type === "identifier" || token.type === "string") {
        output.push(token.type === "string" ? JSON.stringify(token.value) : String(token.value));
      } else if (token.type === "(") {
        operators.push("(");
      } else if (token.type === ")") {
        while (operators.length && operators.at(-1) !== "(") output.push(operators.pop());
        if (operators.pop() !== "(") throw new Error("Mismatched parentheses");
      } else {
        while (operators.length && operators.at(-1) !== "(" && (precedence[operators.at(-1)] > precedence[token.type] || precedence[operators.at(-1)] === precedence[token.type] && token.type !== "^")) {
          output.push(operators.pop());
        }
        operators.push(token.type);
      }
    }
    while (operators.length) {
      const operator = operators.pop();
      if (operator === "(") throw new Error("Mismatched parentheses");
      output.push(operator);
    }
    return output.join(" ");
  }
  function postfixToInfix(expression) {
    const tokens = String(expression).trim().split(/\s+/);
    const stack = [];
    for (const token of tokens) {
      if (/^[+\-*/^]$/.test(token)) {
        const right = stack.pop();
        const left = stack.pop();
        if (left === void 0 || right === void 0) throw new Error("Invalid postfix expression");
        stack.push(`(${left}${token}${right})`);
      } else {
        stack.push(token);
      }
    }
    if (stack.length !== 1) throw new Error("Invalid postfix expression");
    return stack[0];
  }
  function evaluatePostfix(expression) {
    const tokens = String(expression).trim().includes(" ") ? String(expression).trim().split(/\s+/) : String(expression).split("");
    const stack = [];
    for (const token of tokens) {
      if (/^[+\-*/^]$/.test(token)) {
        const right = Number(stack.pop());
        const left = Number(stack.pop());
        if (!Number.isFinite(left) || !Number.isFinite(right)) throw new Error("Invalid postfix expression");
        if (token === "+") stack.push(left + right);
        if (token === "-") stack.push(left - right);
        if (token === "*") stack.push(left * right);
        if (token === "/") stack.push(left / right);
        if (token === "^") stack.push(left ** right);
      } else {
        const number = Number(token);
        if (!Number.isFinite(number)) throw new Error("Postfix evaluation supports numeric operands only");
        stack.push(number);
      }
    }
    if (stack.length !== 1) throw new Error("Invalid postfix expression");
    return stack[0];
  }
  function RegisterRegVars(varName, varType, varValue) {
    const name = String(varName != null ? varName : "").trim();
    if (!name) return "";
    const entry = `${name}:${varType != null ? varType : ""}:${varValue != null ? varValue : ""}`;
    const existingIndex = RegVarFldList.findIndex(
      (value) => value.slice(0, value.indexOf(":")).toLowerCase() === name.toLowerCase()
    );
    if (existingIndex === -1) RegVarFldList.push(entry);
    else RegVarFldList[existingIndex] = entry;
    return "";
  }
  function evaluateFunction(name, args, reactFieldArray, rowNo, context) {
    var _a, _b, _c, _d, _e, _f;
    const [first, second, third] = args;
    const text = (value) => String(value != null ? value : "");
    const numeric = (value) => Number(value);
    const activeDateFormat = (_a = context.dateFormat) != null ? _a : dateFormat;
    const asBoolean = (value) => typeof value === "string" ? !["", "0", "f", "false", "n", "no"].includes(value.trim().toLowerCase()) : Boolean(value);
    function matchingFields(fieldName) {
      return reactFieldArray.filter((field) => field.n.toLowerCase() === text(fieldName).toLowerCase()).sort((left, right) => Number(left.rno) - Number(right.rno));
    }
    function rowExtreme(fieldName, isMinimum) {
      const values = matchingFields(fieldName).map((field, index) => ({ index, value: Number(normalizeValue(field.v)) })).filter((entry) => Number.isFinite(entry.value));
      if (!values.length) return 0;
      const extreme = values.reduce(
        (best, entry) => isMinimum ? Math.min(best, entry.value) : Math.max(best, entry.value),
        values[0].value
      );
      return values.find((entry) => entry.value === extreme).index + 1;
    }
    function dateArgument(value) {
      const date = parseFormulaDate(value, activeDateFormat);
      if (!date) throw new Error("Invalid date");
      return date;
    }
    switch (name.toLowerCase()) {
      case "regvar":
        return RegisterRegVars(text(first), text(second), third);
      case "abs":
        return Math.abs(numeric(first));
      case "ceil":
      case "axpceil":
        return Math.ceil(numeric(first));
      case "floor":
      case "axpfloor":
        return Math.floor(numeric(first));
      case "round":
        return Math.round(numeric(first));
      case "roundoff": {
        const places = Math.max(0, Math.min(12, numeric(second) || 0));
        const factor = 10 ** places;
        return Math.round((numeric(first) + Number.EPSILON) * factor) / factor;
      }
      case "evaluatepower":
        return numeric(first) ** numeric(second);
      case "getinteger":
        return Number.parseInt(first, 10) || 0;
      case "length":
      case "getlength":
        return text(first).length;
      case "substr": {
        const start = Math.max(0, (numeric(second) || 1) - 1);
        const end = args.length > 2 ? start + Math.max(0, numeric(third)) : void 0;
        return text(first).substring(start, end);
      }
      case "upper":
      case "uppercase":
        return text(first).toUpperCase();
      case "lower":
      case "lowercase":
        return text(first).toLowerCase();
      case "trim":
      case "trimall":
        return text(first).trim();
      case "triminbetwnspaces":
        return text(first).replace(/\s/g, "");
      case "isempty":
      case "isemptyvalue":
      case "isvarempty":
        return text(first) === "" ? "T" : "F";
      case "iif":
        return first ? second : third;
      case "val":
        return Number.parseFloat(text(first).replace(/,/g, "")) || 0;
      case "str":
      case "getvarvalue":
        return text(first);
      case "mods":
      case "getmod":
        return numeric(second) === 0 ? 0 : numeric(first) % numeric(second);
      case "extractnum":
        return text(first).replace(/\D/g, "");
      case "removecommas":
        return text(first).replace(/,/g, "") || "0";
      case "findcharpos":
        return text(first).indexOf(text(second));
      case "findandreplace": {
        const search = text(second).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        return text(first).replace(new RegExp(search, "gi"), text(third));
      }
      case "chkuniqchar":
        return new Set(text(first)).size !== text(first).length;
      case "getnthstring":
        return text(first).substring(Math.max(0, numeric(second) || 0));
      case "getseperatorcount": {
        const separator = text(second);
        return separator ? text(first).split(separator).length - 1 : 0;
      }
      case "leftpad":
        return text(first).padStart(numeric(second), text(third) || "0");
      case "rightpad":
        return text(first).padEnd(numeric(second), text(third) || "0");
      case "pad": {
        const targetLength = Math.max(0, numeric(second));
        const character = text(third) || "0";
        let result = text(first);
        while (result.length < targetLength) {
          result = character + result;
          if (result.length < targetLength) result += character;
        }
        return result;
      }
      case "formatval": {
        const places = Math.max(0, Math.min(12, numeric(second) || 2));
        return Number(numeric(first).toFixed(places));
      }
      case "lastdayofmonth": {
        const date = dateArgument(first);
        return formatFormulaDate(new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)), activeDateFormat);
      }
      case "daysinmonth": {
        const date = second === void 0 ? parseFormulaDate(first, activeDateFormat) : null;
        const year = date ? date.getUTCFullYear() : numeric(first);
        const month = date ? date.getUTCMonth() + 1 : numeric(second);
        return new Date(Date.UTC(year, month, 0)).getUTCDate();
      }
      case "validencodedate": {
        const date = new Date(Date.UTC(numeric(first), numeric(second) - 1, numeric(third)));
        return formatFormulaDate(date, activeDateFormat);
      }
      case "addtomonth": {
        return formatFormulaDate(addMonthsClamped(dateArgument(first), numeric(second)), activeDateFormat);
      }
      case "addtodate": {
        const date = dateArgument(first);
        date.setUTCDate(date.getUTCDate() + numeric(second));
        return formatFormulaDate(date, activeDateFormat);
      }
      case "timeelapsed": {
        const milliseconds = Math.abs(dateArgument(second) - dateArgument(first));
        const totalSeconds = Math.floor(milliseconds / 1e3);
        const days = Math.floor(totalSeconds / 86400);
        const hours = Math.floor(totalSeconds % 86400 / 3600);
        const minutes = Math.floor(totalSeconds % 3600 / 60);
        const seconds = totalSeconds % 60;
        return `${days} days, ${hours} hours, ${minutes} minutes, ${seconds} seconds`;
      }
      case "dayselapsed":
      case "datediff":
        return Math.floor(Math.abs(dateArgument(second) - dateArgument(first)) / 864e5);
      case "mandy": {
        const date = dateArgument(first);
        return `${date.getUTCFullYear()}${String(date.getUTCMonth() + 1).padStart(2, "0")}`;
      }
      case "insertcommas":
        return formatFormulaAmount(first, 2, true);
      case "amtword":
        return `Rupees ${amountInWords(first)} Only`;
      case "curramtword": {
        const amountParts = text(first).split(".");
        const wholeWords = amountInWords(amountParts[0]);
        const decimalDigits = (_b = amountParts[1]) != null ? _b : "";
        const decimalWords = decimalDigits ? amountInWords(decimalDigits) : "";
        const major = `${text(second)}${wholeWords}`;
        return decimalWords ? `${major} and ${text(third)} ${decimalWords} only` : `${major} only`;
      }
      case "infixtopostfix":
        return infixToPostfix(first);
      case "postfixtoinfix":
        return postfixToInfix(first);
      case "postfixeval":
        return evaluatePostfix(first);
      case "inputprecedence": {
        return (_c = { ")": 0, "|": 1, "&": 3, "+": 5, "-": 5, "*": 7, "/": 7, "^": 10, ">": 10, "<": 10, "=": 10, "#": 10, "$": 10, "(": 13 }[text(first)]) != null ? _c : 11;
      }
      case "stackprecedence": {
        return (_d = { "(": 0, "|": 2, "&": 4, "+": 6, "-": 6, "*": 8, "/": 8, "^": 9, ">": 9, "<": 9, "=": 9, "#": 9, "$": 9 }[text(first)]) != null ? _d : 12;
      }
      case "isoperator":
        return /^[+\-*/^=<>#&|$]$/.test(text(first));
      case "encode":
        return encodeBase64(first);
      case "decode":
        return decodeBase64(first);
      case "dtoc":
      case "ctod":
        return formatFormulaDate(dateArgument(first), activeDateFormat);
      case "cmonthyear": {
        const date = dateArgument(first);
        return `${date.toLocaleString("en", { month: "long", timeZone: "UTC" })} ${date.getUTCFullYear()}`;
      }
      case "stuff": {
        const source = text(first);
        const position = Math.max(0, Math.min(source.length, numeric(third)));
        return source.slice(0, position) + text(second) + source.slice(position);
      }
      case "rnd": {
        const step = numeric(second);
        if (!step) return 0;
        return Math.round(numeric(first) * 100 / step) * step / 100;
      }
      case "formatamount": {
        const amount = numeric(first);
        const shouldGroup = String((_e = args[2]) != null ? _e : "").toLowerCase() === "t" || ["true", "t"].includes(String((_f = args[3]) != null ? _f : "").toLowerCase());
        const places = numeric(second) || 2;
        const formatted = formatFormulaAmount(Math.abs(amount), places, shouldGroup);
        const negativeRep = text(args[4]);
        const positiveRep = text(args[5]);
        if ((negativeRep === "br" || positiveRep === "br") && amount < 0) return `(${formatted})`;
        const suffix = amount < 0 ? negativeRep : positiveRep;
        return `${formatted}${suffix && suffix !== "br" ? ` ${suffix}` : ""}`;
      }
      case "formataccamount": {
        const amount = numeric(first);
        const formatted = formatFormulaAmount(
          Math.abs(amount),
          numeric(second) || 2,
          ["true", "t"].includes(String(third).toLowerCase())
        );
        const signMode = text(args[3]).toLowerCase();
        const currency = text(args[4]);
        if (currency.toLowerCase() === "br" && (signMode === "a" || signMode === "e" ? amount < 0 : amount > 0)) {
          return `(${formatted})`;
        }
        return currency ? `${formatted} ${currency}` : formatted;
      }
      case "date": {
        const now = /* @__PURE__ */ new Date();
        return formatFormulaDate(new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate())), activeDateFormat);
      }
      case "time":
        return (/* @__PURE__ */ new Date()).toTimeString().slice(0, 8);
      case "checkemail":
        return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(text(first));
      case "convertmd5":
        return md5(first);
      case "makedate": {
        const date = new Date(Date.UTC(numeric(third), numeric(second) - 1, numeric(first)));
        return formatFormulaDate(date, activeDateFormat);
      }
      case "dayofdate":
        return dateArgument(first).getUTCDate();
      case "monthofdate":
        return dateArgument(first).getUTCMonth() + 1;
      case "yearofdate":
        return dateArgument(first).getUTCFullYear();
      case "getmin":
        return rowExtreme(first, true);
      case "getmax":
        return rowExtreme(first, false);
      case "networkdays": {
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
      case "days360": {
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
      case "getvalue": {
        const requestedRow = args.length > 1 ? Number(second) : Number(rowNo);
        const entry = reactFieldArray.find(
          (field) => field.n.toLowerCase() === text(first).toLowerCase() && Number(field.rno) === requestedRow
        );
        return entry ? normalizeValue(entry.v) : "";
      }
      case "total": {
        return reactFieldArray.filter((field) => field.n.toLowerCase() === text(first).toLowerCase()).reduce((sum, field) => sum + (Number(normalizeValue(field.v)) || 0), 0);
      }
      case "getrowcount": {
        return new Set(matchingFields(first).map((field) => field.rno)).size;
      }
      case "stringpos": {
        const separator = third === void 0 || third === "" ? "," : text(third);
        return text(second).split(separator).indexOf(text(first));
      }
      case "getrow": {
        const match = reactFieldArray.find(
          (field) => field.n.toLowerCase() === text(first).toLowerCase() && String(field.v) === String(second)
        );
        return match ? Number(match.rno) : -1;
      }
      case "sum":
      case "sumtill": {
        const limit = name.toLowerCase() === "sumtill" && args.length > 3 ? Number(args[3]) : Infinity;
        const matchingRows = new Set(reactFieldArray.filter((field) => field.n.toLowerCase() === text(first).toLowerCase() && String(field.v) === String(second) && Number(field.rno) <= limit).map((field) => Number(field.rno)));
        return reactFieldArray.filter((field) => field.n.toLowerCase() === text(third).toLowerCase() && matchingRows.has(Number(field.rno))).reduce((sum, field) => sum + (Number(normalizeValue(field.v)) || 0), 0);
      }
      case "getallvalues": {
        return matchingFields(first).map((field) => {
          var _a2;
          return String((_a2 = field.v) != null ? _a2 : "");
        }).filter(Boolean).join(",");
      }
      default:
        throw new Error(`Unsupported function: ${name}`);
    }
  }
  function calculate(expression, resolveVariable, reactFieldArray, rowNo, context = {}) {
    const tokens = tokenize(expression);
    let position = 0;
    function parsePrimary() {
      var _a, _b, _c, _d, _e, _f, _g;
      const token = tokens[position++];
      if (!token) throw new Error("Expected a value");
      if (token.type === "number") return token.value;
      if (token.type === "string") return token.value;
      if (token.type === "identifier") {
        if (((_a = tokens[position]) == null ? void 0 : _a.type) === "(") {
          position++;
          const args = [];
          if (((_b = tokens[position]) == null ? void 0 : _b.type) !== ")") {
            do {
              if (token.value.toLowerCase() === "total" && args.length === 0 && ((_c = tokens[position]) == null ? void 0 : _c.type) === "identifier" && ((_d = tokens[position + 1]) == null ? void 0 : _d.type) !== "(") {
                args.push(tokens[position++].value);
              } else {
                args.push(parseOr());
              }
              if (((_e = tokens[position]) == null ? void 0 : _e.type) !== ",") break;
              position++;
            } while (position < tokens.length);
          }
          if (((_f = tokens[position++]) == null ? void 0 : _f.type) !== ")") throw new Error("Expected closing parenthesis");
          return evaluateFunction(token.value, args, reactFieldArray, rowNo, context);
        }
        const value = resolveVariable(token.value);
        if (value === void 0) throw new Error(`Unknown variable: ${token.value}`);
        return value;
      }
      if (token.type === "(") {
        const value = parseOr();
        if (((_g = tokens[position++]) == null ? void 0 : _g.type) !== ")") throw new Error("Expected closing parenthesis");
        return value;
      }
      throw new Error("Expected a number, variable, or parenthesized expression");
    }
    function parsePower() {
      var _a;
      const left = parsePrimary();
      if (((_a = tokens[position]) == null ? void 0 : _a.type) === "^") {
        position++;
        return Number(left) ** Number(parseUnary());
      }
      return left;
    }
    function parseUnary() {
      var _a;
      const operator = (_a = tokens[position]) == null ? void 0 : _a.type;
      if (operator === "+" || operator === "-") {
        position++;
        const value = Number(parseUnary());
        return operator === "-" ? -value : value;
      }
      return parsePower();
    }
    function parseMultiplicative() {
      var _a;
      let value = parseUnary();
      while (["*", "/", "%"].includes((_a = tokens[position]) == null ? void 0 : _a.type)) {
        const operator = tokens[position++].type;
        const right = Number(parseUnary());
        const left = Number(value);
        if (operator === "*") value = left * right;
        if (operator === "/") value = left / right;
        if (operator === "%") value = left % right;
      }
      return value;
    }
    function parseAdditive() {
      var _a;
      let value = parseMultiplicative();
      while (["+", "-"].includes((_a = tokens[position]) == null ? void 0 : _a.type)) {
        const operator = tokens[position++].type;
        const right = parseMultiplicative();
        value = operator === "+" ? value + right : Number(value) - Number(right);
      }
      return value;
    }
    function parseComparison() {
      var _a;
      let value = parseAdditive();
      while (["=", "==", "!=", "#", "<", ">", "<=", ">="].includes((_a = tokens[position]) == null ? void 0 : _a.type)) {
        const operator = tokens[position++].type;
        const right = parseAdditive();
        if (operator === "=" || operator === "==") value = value == right;
        if (operator === "!=" || operator === "#") value = value != right;
        if (operator === "<") value = value < right;
        if (operator === ">") value = value > right;
        if (operator === "<=") value = value <= right;
        if (operator === ">=") value = value >= right;
      }
      return value;
    }
    function parseAnd() {
      var _a;
      let value = parseComparison();
      while (["&", "&&"].includes((_a = tokens[position]) == null ? void 0 : _a.type)) {
        position++;
        const right = parseComparison();
        value = Boolean(value) && Boolean(right);
      }
      return value;
    }
    function parseOr() {
      var _a;
      let value = parseAnd();
      while (["|", "||"].includes((_a = tokens[position]) == null ? void 0 : _a.type)) {
        position++;
        const right = parseAnd();
        value = Boolean(value) || Boolean(right);
      }
      return value;
    }
    const result = parseOr();
    if (position !== tokens.length) throw new Error("Unexpected token");
    return result;
  }

  // form-studio/src/core/fieldRule.js
  var GLOBAL_PREFIX = "global_";
  var GLOBALS = {};
  var GLOBALS_VERSION = 0;
  var setRuleGlobals = (values) => {
    const next = {};
    for (const [k, v] of Object.entries(values && typeof values === "object" ? values : {})) if (/^[A-Za-z_]\w*$/.test(k) && (v === null || ["string", "number", "boolean"].includes(typeof v))) next[k] = v;
    GLOBALS = next;
    GLOBALS_VERSION += 1;
  };
  var getRuleGlobals = () => GLOBALS;
  var NO = /* @__PURE__ */ new Set(["false", "f", "0", "no", "n"]);
  var ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;
  function ruleResult(v) {
    if (v === true) return true;
    if (v === false) return false;
    if (typeof v === "number") return v !== 0 && !Number.isNaN(v);
    if (typeof v === "string") {
      const t = v.trim().toLowerCase();
      if (t === "") return null;
      return !NO.has(t);
    }
    return null;
  }
  var forParser = (v) => {
    if (v === void 0 || v === null) return "";
    if (Array.isArray(v)) return v.join(",");
    if (typeof v === "object") return "";
    if (typeof v === "string") {
      const m = ISO_DATE.exec(v);
      if (m) return `${m[3]}/${m[2]}/${m[1]}`;
    }
    return v;
  };
  function evaluateRule(expr, values) {
    const out = evaluateExpression(expr, values);
    return out === null ? null : ruleResult(out);
  }
  function evaluateExpression(expr, values) {
    const text = String(expr != null ? expr : "").trim();
    if (!text) return null;
    let arr = [];
    const put = (n, v, rno) => {
      if (n && !n.includes("__") && /^[A-Za-z_][\w]*$/.test(n)) arr = RegisterVariable(arr, { n, v: forParser(v), rno });
    };
    for (const [n, v] of Object.entries(GLOBALS)) {
      put(n, v, 1);
      put(`${GLOBAL_PREFIX}${n}`, v, 1);
    }
    for (const [n, v] of Object.entries(values || {})) {
      if (Array.isArray(v) && v.length && v.every((r) => r && typeof r === "object" && !Array.isArray(r))) {
        v.forEach((row, i) => Object.entries(row).forEach(([k, x]) => put(k, x, i + 1)));
      } else put(n, v, 1);
    }
    try {
      return Evaluate(text, "__rule", 1, { reactFieldArray: arr });
    } catch {
      return null;
    }
  }
  var withBlanks = (ids, values) => {
    const out = { ...values || {} };
    for (const id of ids || []) if (id && out[id] === void 0) out[id] = "";
    return out;
  };
  function fieldRuleError(field, value, values) {
    var _a, _b, _c;
    const rule = field == null ? void 0 : field.rule;
    if (!rule || !String((_a = rule.expr) != null ? _a : "").trim()) return null;
    if (value === void 0 || value === null || value === "" || Array.isArray(value) && value.length === 0) return null;
    const id = (_b = field.id) != null ? _b : field.name;
    const ok = evaluateRule(rule.expr, { ...values || {}, [id]: value });
    if (ok !== false) return null;
    return String((_c = rule.message) != null ? _c : "").trim() || `${field.label || field.caption || id} is not valid`;
  }

  // form-studio/src/core/fieldCalc.js
  var CALC_TYPES = ["text", "wholeNumber", "number", "date", "list"];
  var kindOf = (f) => {
    var _a;
    return String((_a = f == null ? void 0 : f.type) != null ? _a : "").toLowerCase();
  };
  var CALC_KINDS = CALC_TYPES.map((x) => x.toLowerCase());
  var hasCalc = (f) => {
    var _a;
    return !!(f && f.calc && String((_a = f.calc.expr) != null ? _a : "").trim());
  };
  var canCalc = (f) => !!f && CALC_KINDS.includes(kindOf(f)) && !f.multi;
  var isEmpty = (v) => v === void 0 || v === null || v === "" || Array.isArray(v) && v.length === 0;
  var same = (a, b) => String(a != null ? a : "") === String(b != null ? b : "");
  var LITERAL = /"[^"]*"|'[^']*'/g;
  var WORD = /[A-Za-z_]\w*/g;
  function usedFields(expr, ids) {
    const byLower = new Map(ids.map((i) => [String(i).toLowerCase(), i]));
    const text = String(expr != null ? expr : "").replace(LITERAL, '""');
    const out = /* @__PURE__ */ new Set();
    let m;
    WORD.lastIndex = 0;
    while (m = WORD.exec(text)) {
      if (/^\s*\(/.test(text.slice(WORD.lastIndex))) continue;
      const id = byLower.get(m[0].toLowerCase());
      if (id !== void 0) out.add(id);
    }
    return [...out];
  }
  function fitCalc(field, raw) {
    if (raw === null || raw === void 0) return "";
    const kind = kindOf(field);
    if (typeof raw === "boolean") return kind === "text" ? String(raw) : "";
    const text = String(raw).trim();
    if (text === "") return "";
    switch (kind) {
      case "text":
        return text;
      case "wholenumber":
      case "number": {
        const n = Number(text);
        if (!Number.isFinite(n)) return "";
        if (kind === "wholenumber" && !Number.isInteger(n)) return "";
        return String(n);
      }
      case "date": {
        const dmy = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(text);
        if (dmy) return `${dmy[3]}-${dmy[2].padStart(2, "0")}-${dmy[1].padStart(2, "0")}`;
        return /^\d{4}-\d{2}-\d{2}$/.test(text) ? text : "";
      }
      case "list": {
        const hit = (field.options || []).find((o) => String(o).trim().toLowerCase() === text.toLowerCase());
        return hit === void 0 ? "" : hit;
      }
      default:
        return "";
    }
  }
  var MEMORY = /* @__PURE__ */ new Map();
  var MEMORY_FIELDS = 500;
  var MEMORY_PER_FIELD = 400;
  var WORDS = /* @__PURE__ */ new Map();
  var ANY_WORD = /[A-Za-z_]\w*/g;
  var CLOCK = /\btime\s*\(/i;
  var wordsOf = (expr) => {
    let w = WORDS.get(expr);
    if (!w) {
      if (WORDS.size > 2e3) WORDS.clear();
      w = [...new Set((expr.match(ANY_WORD) || []).map((x) => x.toLowerCase()))];
      WORDS.set(expr, w);
    }
    return w;
  };
  var part = (v) => v === void 0 || v === null ? "" : typeof v === "object" ? JSON.stringify(v) : String(v);
  var BARE = /^\s*([A-Za-z_]\w*)\s*$/;
  function copied(expr, cur, names) {
    const m = BARE.exec(expr);
    if (!m) return void 0;
    const w = m[1].toLowerCase();
    const k = names.get(w);
    if (k !== void 0) {
      const v = cur[k];
      return Array.isArray(v) || v && typeof v === "object" ? void 0 : part(v);
    }
    const g = getRuleGlobals();
    const bare = w.startsWith("global_") ? w.slice(7) : w;
    for (const key in g) if (key.toLowerCase() === bare) return part(g[key]);
    return void 0;
  }
  function answer(id, expr, cur, names, columns) {
    const plain = copied(expr, cur, names);
    if (plain !== void 0) return plain;
    if (CLOCK.test(expr)) return evaluateExpression(expr, cur);
    const sig = `${(/* @__PURE__ */ new Date()).toDateString()}${wordsOf(expr).map((w) => {
      const k = names.get(w);
      if (k !== void 0) return part(cur[k]);
      const col = columns && columns.get(w);
      if (col) {
        const rows = cur[col[0]];
        return Array.isArray(rows) ? rows.map((r) => part(r && r[col[1]])).join("") : "";
      }
      const g = getRuleGlobals();
      const bare = w.startsWith("global_") ? w.slice(7) : w;
      for (const k2 in g) if (k2.toLowerCase() === bare) return part(g[k2]);
      return "";
    }).join("")}`;
    const key = `${id}${expr}`;
    let m = MEMORY.get(key);
    if (!m) {
      if (MEMORY.size >= MEMORY_FIELDS) MEMORY.clear();
      m = /* @__PURE__ */ new Map();
      MEMORY.set(key, m);
    }
    if (m.has(sig)) return m.get(sig);
    const out = evaluateExpression(expr, cur);
    if (m.size >= MEMORY_PER_FIELD) m.clear();
    m.set(sig, out);
    return out;
  }
  function applyCalcs(fields, values, idOf = (f) => f.id, extraIds = [], columns = null) {
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
        const { [id]: _own, ...view } = cur;
        const others = new Map(names);
        others.delete(String(id).toLowerCase());
        const next = reads.some((x) => isEmpty(cur[x])) ? "" : fitCalc(f, answer(id, f.calc.expr, view, others, columns));
        if (!same(cur[id], next)) {
          cur = { ...cur, [id]: next };
          changed = true;
        }
      }
      if (!changed) break;
    }
    return cur;
  }
  function applyRowCalcs(fields, row, outer, idOf = (f) => f.id) {
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
  function applyFormCalcs(fields, grids, values, idOf = (f) => f.id) {
    const gridIds = new Set(grids.map((g) => g.id));
    let cur = values;
    const columns = /* @__PURE__ */ new Map();
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

  // form-studio/src/core/formLogicEntry.js
  var ISO_DATE2 = /^\d{4}-\d\d-\d\d$/;
  function runConformance(conformance) {
    let fields = [];
    const put = (n, v, rno) => {
      fields = RegisterVariable(fields, { n, v: typeof v === "string" && ISO_DATE2.test(v) ? v.split("-").reverse().join("/") : v, rno });
    };
    for (const [n, v] of Object.entries(conformance.sample.fields)) put(n, v, 1);
    for (const [n, values] of Object.entries(conformance.sample.rows)) values.forEach((v, i) => put(n, v, i + 1));
    const failures = [];
    for (const c of conformance.cases) {
      let got;
      try {
        got = String(Evaluate(c.expr, "__x", 1, { reactFieldArray: fields }));
      } catch (e) {
        got = `ERROR: ${e && e.message}`;
      }
      if (got !== c.expect) failures.push({ expr: c.expr, expected: c.expect, got });
    }
    return { total: conformance.cases.length, passed: conformance.cases.length - failures.length, failures };
  }
  return __toCommonJS(formLogicEntry_exports);
})();
