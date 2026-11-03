// Fills in what the form logic needs and a small JavaScript engine may not have, only where it is missing: TextEncoder and TextDecoder (UTF-8), atob and btoa, Intl.NumberFormat for the
// two ways the logic formats a number (en-IN with lakh grouping, en-US), and the English month name of Date.prototype.toLocaleString. Load it BEFORE form-logic.bundle.js (or before the
// modules). On the web, and in any engine that has all of these, it changes nothing. Plain script, no modules, no syntax newer than ES2015. docs/FORM_LOGIC_FOR_MOBILE.md.
(function (g) {
  'use strict';

  // ---- TextEncoder / TextDecoder (UTF-8) ----
  if (typeof g.TextEncoder === 'undefined') {
    g.TextEncoder = function TextEncoder() {};
    g.TextEncoder.prototype.encoding = 'utf-8';
    g.TextEncoder.prototype.encode = function (input) {
      var s = input === undefined ? '' : String(input), out = [], i, c, d;
      for (i = 0; i < s.length; i++) {
        c = s.charCodeAt(i);
        if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length && (d = s.charCodeAt(i + 1)) >= 0xdc00 && d <= 0xdfff) { c = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00); i++; }
        else if (c >= 0xd800 && c <= 0xdfff) c = 0xfffd;                                     // a lone surrogate is written as the replacement character, as the standard says
        if (c < 0x80) out.push(c);
        else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
        else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
        else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
      }
      return new Uint8Array(out);
    };
  }
  if (typeof g.TextDecoder === 'undefined') {
    g.TextDecoder = function TextDecoder() {};
    g.TextDecoder.prototype.encoding = 'utf-8';
    g.TextDecoder.prototype.decode = function (input) {
      var b = input === undefined ? [] : (input.buffer && input.byteLength !== undefined ? new Uint8Array(input.buffer, input.byteOffset, input.byteLength) : new Uint8Array(input));
      var s = '', i = 0, c, n, cp, j, lo, hi, bad;
      while (i < b.length) {
        c = b[i];
        if (c < 0x80) { s += String.fromCharCode(c); i++; continue; }
        n = c >= 0xc2 && c < 0xe0 ? 1 : c >= 0xe0 && c < 0xf0 ? 2 : c >= 0xf0 && c < 0xf5 ? 3 : 0;      // how many continuation bytes follow
        if (n === 0) { s += '\ufffd'; i++; continue; }
        cp = n === 1 ? c & 31 : n === 2 ? c & 15 : c & 7;
        bad = 0;
        for (j = 1; j <= n; j++) {
          lo = 0x80; hi = 0xbf;
          if (j === 1) { if (c === 0xe0) lo = 0xa0; else if (c === 0xed) hi = 0x9f; else if (c === 0xf0) lo = 0x90; else if (c === 0xf4) hi = 0x8f; }
          if (i + j >= b.length || b[i + j] < lo || b[i + j] > hi) { bad = j; break; }
          cp = (cp << 6) | (b[i + j] & 63);
        }
        if (bad) { s += '\ufffd'; i += bad; continue; }                                    // one replacement character for the bytes that did belong together
        if (cp >= 0x10000) { cp -= 0x10000; s += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 1023)); } else s += String.fromCharCode(cp);
        i += n + 1;
      }
      return s.charCodeAt(0) === 0xfeff ? s.slice(1) : s;                                    // a leading byte order mark is dropped, as the standard decoder does
    };
  }

  // ---- atob / btoa ----
  var B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  if (typeof g.btoa === 'undefined') {
    g.btoa = function btoa(input) {
      var s = String(input), out = '', i = 0, a, b, c;
      for (i = 0; i < s.length; i++) if (s.charCodeAt(i) > 255) throw new Error('InvalidCharacterError: the text has a character outside Latin1');
      for (i = 0; i < s.length; i += 3) {
        a = s.charCodeAt(i); b = i + 1 < s.length ? s.charCodeAt(i + 1) : NaN; c = i + 2 < s.length ? s.charCodeAt(i + 2) : NaN;
        out += B64.charAt(a >> 2) + B64.charAt(((a & 3) << 4) | (b >> 4 || 0)) + (b !== b ? '=' : B64.charAt(((b & 15) << 2) | (c >> 6 || 0))) + (c !== c ? '=' : B64.charAt(c & 63));
      }
      return out;
    };
  }
  if (typeof g.atob === 'undefined') {
    g.atob = function atob(input) {
      var s = String(input).replace(/[\t\n\f\r ]+/g, ''), out = '', buf = 0, bits = 0, i, v;
      if (s.length % 4 === 0) s = s.replace(/={1,2}$/, '');
      if (s.length % 4 === 1 || /[^A-Za-z0-9+/]/.test(s)) throw new Error('InvalidCharacterError: the text is not base64');
      for (i = 0; i < s.length; i++) {
        v = B64.indexOf(s.charAt(i)); buf = (buf << 6) | v; bits += 6;
        if (bits >= 8) { bits -= 8; out += String.fromCharCode((buf >> bits) & 255); buf &= (1 << bits) - 1; }
      }
      return out;
    };
  }

  // ---- Intl.NumberFormat, for the two ways the logic uses it ----
  // en-IN and en-US, useGrouping, minimumFractionDigits and maximumFractionDigits: nothing else is used (formatFormulaAmount in axExpParser.js).
  var okNumber = false;
  try {
    okNumber = typeof g.Intl === 'object' && g.Intl !== null && typeof g.Intl.NumberFormat === 'function' &&
      new g.Intl.NumberFormat('en-IN', { useGrouping: true, minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(1234567.5) === '12,34,567.50' &&
      new g.Intl.NumberFormat('en-US', { useGrouping: false, minimumFractionDigits: 0, maximumFractionDigits: 0 }).format(1234567.5) === '1234568' &&
      new g.Intl.NumberFormat('en-US', { useGrouping: true, minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(-1234.25) === '-1,234.3';
  } catch (_e) { okNumber = false; }
  if (!okNumber) {
    var group = function (digits, indian) {
      var head = digits, tail = '';
      if (indian) { if (digits.length > 3) { tail = digits.slice(-3); head = digits.slice(0, -3).replace(/\B(?=(\d{2})+(?!\d))/g, ',') + ','; } else return digits; return head + tail; }
      return digits.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    };
    var numberFormat = function (locale, options) {
      if (!(this instanceof numberFormat)) return new numberFormat(locale, options);
      var o = options || {};
      this.indian = String(locale) === 'en-IN';
      this.grouping = o.useGrouping === undefined ? true : !!o.useGrouping;
      this.min = o.minimumFractionDigits === undefined ? 0 : Math.max(0, Math.min(100, o.minimumFractionDigits | 0));
      this.max = o.maximumFractionDigits === undefined ? Math.max(this.min, 3) : Math.max(this.min, Math.min(100, o.maximumFractionDigits | 0));
    };
    // The number as the standard does it: from its shortest decimal text (1.005 is "1.005", so it rounds to 1.01, where toFixed would say 1.00), ties away from zero.
    var decimal = function (x, places) {
      var m = /^(\d+)(?:\.(\d+))?(?:e([+-]\d+))?$/.exec(String(x)), d = m[1] + (m[2] || ''), pos = m[1].length + (m[3] ? parseInt(m[3], 10) : 0), i, zeros = '', up, carry, digits;
      if (pos <= 0) { for (i = 0; i < 1 - pos; i++) zeros += '0'; d = zeros + d; pos = 1; zeros = ''; }
      if (pos > d.length) { for (i = d.length; i < pos; i++) zeros += '0'; d += zeros; }
      var whole = d.slice(0, pos), frac = d.slice(pos);
      if (frac.length > places) {
        up = frac.charCodeAt(places) >= 53;                                                   // the next digit is 5 or more
        digits = (whole + frac.slice(0, places)).split('');
        if (up) { for (i = digits.length - 1, carry = true; i >= 0 && carry; i--) { if (digits[i] === '9') digits[i] = '0'; else { digits[i] = String.fromCharCode(digits[i].charCodeAt(0) + 1); carry = false; } } if (carry) digits.unshift('1'); }
        whole = digits.slice(0, digits.length - places).join(''); frac = digits.slice(digits.length - places).join('');
      }
      while (frac.length < places) frac += '0';
      return { whole: whole.replace(/^0+(?=\d)/, ''), frac: frac };
    };
    numberFormat.prototype.format = function (value) {
      var n = Number(value);
      if (n !== n) return 'NaN';
      if (n === Infinity || n === -Infinity) return n < 0 ? '-\u221e' : '\u221e';
      var neg = n < 0 || (n === 0 && 1 / n < 0);
      var parts = decimal(Math.abs(n), this.max), frac = parts.frac;
      while (frac.length > this.min && frac.charAt(frac.length - 1) === '0') frac = frac.slice(0, -1);
      return (neg ? '-' : '') + (this.grouping ? group(parts.whole, this.indian) : parts.whole) + (frac ? '.' + frac : '');
    };
    numberFormat.prototype.resolvedOptions = function () { return { locale: this.indian ? 'en-IN' : 'en-US', minimumFractionDigits: this.min, maximumFractionDigits: this.max, useGrouping: this.grouping }; };
    if (typeof g.Intl !== 'object' || g.Intl === null) g.Intl = {};
    g.Intl.NumberFormat = numberFormat;
  }

  // ---- the English month name: new Date(...).toLocaleString('en', { month: 'long', timeZone: 'UTC' }) ----
  var okMonth = false;
  try { okMonth = new Date(0).toLocaleString('en', { month: 'long', timeZone: 'UTC' }) === 'January'; } catch (_e) { okMonth = false; }
  if (!okMonth) {
    var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    var original = Date.prototype.toLocaleString;
    Date.prototype.toLocaleString = function toLocaleString(locale, options) {
      var keys = options && typeof options === 'object' ? Object.keys(options) : [];
      if ((locale === 'en' || locale === 'en-US') && keys.length === 2 && options.month === 'long' && options.timeZone === 'UTC') return MONTHS[this.getUTCMonth()];
      return original.apply(this, arguments);
    };
  }
})(typeof globalThis !== 'undefined' ? globalThis : typeof self !== 'undefined' ? self : this);
