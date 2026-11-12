// Reference implementation of the Connectum mobile avatar / chat-tile colour
// rules. Port of lib/core/utils/avatar_palette.dart, lib/core/widgets/app_avatar.dart,
// lib/core/widgets/conversation_avatar.dart and the sender-name colour of
// lib/features/conversation/widgets/message_bubble.dart. No dependencies.
// Checked against avatar-color-vectors.json by avatar-color.test.ts.
//
// Case mapping: Dart lower/upper-cases ONE code point at a time (simple
// mappings: no final sigma, no sharp s -> SS, U+0130 -> "i"), JS uses the full
// Unicode mappings, so JS toLowerCase()/toUpperCase() give another palette
// index for names with U+0130, a final sigma, etc. dart-case-map.json is Dart's
// own table (generated from the Dart VM); this file never calls JS case functions.
import caseMap from "./dart-case-map.json" with { type: "json" };

const toMap = (rows: [number, number[]][]) => new Map<number, number[]>(rows);
const LOWER = toMap(caseMap.lower as [number, number[]][]);
const UPPER = toMap(caseMap.upper as [number, number[]][]);

/** Dart String.toLowerCase / toUpperCase; lone surrogates pass through. */
function mapCase(s: string, table: Map<number, number[]>): string {
  let out = "";
  for (const ch of s) {
    const cp = ch.codePointAt(0)!;
    const to = table.get(cp);
    out += to ? String.fromCodePoint(...to) : ch;
  }
  return out;
}
export const dartLower = (s: string): string => mapCase(s, LOWER);
export const dartUpper = (s: string): string => mapCase(s, UPPER);

export interface AvatarHue {
  name: string;
  hue: number;
  foregroundSaturation: number;
  foregroundLightness: number;
}

/** Same order as AvatarPalette.hues; the index is the hash result. */
export const HUES: readonly AvatarHue[] = [
  { name: "teal", hue: 178, foregroundSaturation: 0.45, foregroundLightness: 0.32 },
  { name: "cyan", hue: 195, foregroundSaturation: 0.85, foregroundLightness: 0.3 },
  { name: "sky blue", hue: 207, foregroundSaturation: 0.85, foregroundLightness: 0.32 },
  { name: "blue", hue: 218, foregroundSaturation: 0.85, foregroundLightness: 0.36 },
  { name: "cobalt", hue: 228, foregroundSaturation: 0.75, foregroundLightness: 0.38 },
  { name: "indigo", hue: 244, foregroundSaturation: 0.6, foregroundLightness: 0.4 },
  { name: "violet", hue: 262, foregroundSaturation: 0.6, foregroundLightness: 0.4 },
  { name: "purple", hue: 276, foregroundSaturation: 0.6, foregroundLightness: 0.4 },
  { name: "plum", hue: 296, foregroundSaturation: 0.55, foregroundLightness: 0.4 },
  { name: "rose", hue: 338, foregroundSaturation: 0.75, foregroundLightness: 0.4 },
  { name: "slate", hue: 215, foregroundSaturation: 0.25, foregroundLightness: 0.38 },
  { name: "ocean", hue: 200, foregroundSaturation: 0.9, foregroundLightness: 0.3 },
];

export const BACKGROUND_SATURATION = 0.75;
export const BACKGROUND_LIGHTNESS = 0.94;

/** AppColors.avatarText / AppColors.avatarBg: an empty name, and every avatar without a kind. */
export const NEUTRAL = { foreground: "#4A5B7A", background: "#EDF2FA" };
/** AppColors.primaryBright: the tile accent when the name is empty. */
export const PRIMARY_BRIGHT = "#0078E8";
/** AppColors.senderInks, in order. */
export const SENDER_INKS = ["#7A2E9E", "#0F766E", "#A12B55", "#2F6B4F", "#A33B3B", "#9A3B7B"];

// Dart String.trim(): Unicode White_Space plus U+FEFF. JS String.trim() misses U+0085.
const DART_WS = "\\t\\n\\v\\f\\r \\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF";
const TRIM = new RegExp(`^[${DART_WS}]+|[${DART_WS}]+$`, "g");
export const dartTrim = (s: string): string => s.replace(TRIM, "");

// Dart RegExp \s is the ECMAScript one, so JS /\s+/ is the same here.
const LETTER_OR_DIGIT = /^[\p{L}\p{N}]/u;

/** Unicode code points (Dart String.runes). */
const runes = (s: string): number[] => Array.from(s, (c) => c.codePointAt(0)!);

/** AvatarPalette.indexOf: -1 for an empty name, else 0..11. */
export function paletteIndex(name: string): number {
  const r = runes(dartLower(dartTrim(name)));
  if (r.length === 0) return -1;
  return (r[0] * 31 + r[r.length - 1] * 17 + r.length * 13) % HUES.length;
}

const hex2 = (n: number) => n.toString(16).padStart(2, "0").toUpperCase();

/** Flutter HSLColor.toColor(); h in degrees, s and l in 0..1. Returns #RRGGBB. */
export function hslToHex(h: number, s: number, l: number): string {
  const chroma = (1 - Math.abs(2 * l - 1)) * s;
  const secondary = chroma * (1 - Math.abs(((h / 60) % 2) - 1));
  const match = l - chroma / 2;
  let r: number, g: number, b: number;
  if (h < 60) [r, g, b] = [chroma, secondary, 0];
  else if (h < 120) [r, g, b] = [secondary, chroma, 0];
  else if (h < 180) [r, g, b] = [0, chroma, secondary];
  else if (h < 240) [r, g, b] = [0, secondary, chroma];
  else if (h < 300) [r, g, b] = [secondary, 0, chroma];
  else [r, g, b] = [chroma, 0, secondary];
  const c = (v: number) => hex2(Math.round((v + match) * 255));
  return `#${c(r)}${c(g)}${c(b)}`;
}

export interface AvatarColors {
  foreground: string;
  background: string;
}

/** AvatarPalette.fromName. */
export function avatarColors(name: string): AvatarColors {
  const i = paletteIndex(name);
  if (i < 0) return { ...NEUTRAL };
  const h = HUES[i];
  return {
    foreground: hslToHex(h.hue, h.foregroundSaturation, h.foregroundLightness),
    background: hslToHex(h.hue, BACKGROUND_SATURATION, BACKGROUND_LIGHTNESS),
  };
}

/** The letter of a person tile (AppAvatar kind person): first letter or digit, else the first character. */
export function personLetter(name: string): string {
  const r = runes(dartTrim(name));
  if (r.length === 0) return "?";
  const pick = r.find((c) => LETTER_OR_DIGIT.test(String.fromCodePoint(c))) ?? r[0];
  return dartUpper(String.fromCodePoint(pick));
}

/**
 * Initials of an avatar without a kind (neutral tile, accent tile): the first
 * UTF-16 unit of the first two words that start with a letter or digit.
 * Quirk kept on purpose: a word that starts with an astral letter gives a lone
 * surrogate (the app then throws while drawing it).
 */
export function plainInitials(name: string): string {
  const parts = dartTrim(name)
    .split(/\s+/)
    .filter((p) => p.length > 0 && LETTER_OR_DIGIT.test(p));
  if (parts.length === 0) return "?";
  return parts
    .slice(0, 2)
    .map((p) => dartUpper(p[0]))
    .join("");
}

/** Sender name colour in a group bubble (the raw sender string, lower-cased, NOT trimmed). */
export function senderInk(sender: string): string {
  let h = 0;
  const s = dartLower(sender);
  for (let i = 0; i < s.length; i++) {
    h = (h * 31 + s.charCodeAt(i)) & 0x7fffffff;
  }
  return SENDER_INKS[h % SENDER_INKS.length];
}

export type AvatarKind = "person" | "group" | "ticket";

const CARE = /^care-[A-Za-z0-9._-]+$/;
const RECORD = /^rec-(.+)-(\d+)$/i;

/**
 * ConversationAvatarSpec.of. `title` is the title the app shows: the peer's
 * lower-case username for a direct message, the server's thread title when
 * there is one, else the tidied group name.
 */
export function conversationSpec(convId: string, kind: string, title: string): { seedName: string; avatarKind: AvatarKind } {
  if (kind === "dm") return { seedName: title, avatarKind: "person" };
  const group = convId.startsWith("group:") ? convId.substring(6) : null;
  const isRecord = group !== null && RECORD.test(dartTrim(group));
  const isCare = group !== null && CARE.test(dartTrim(group));
  const hasPersonName = isCare && title.length > 0 && title !== group;
  return {
    seedName: title,
    avatarKind: hasPersonName ? "person" : isRecord ? "ticket" : "group",
  };
}

export interface ConversationAvatar {
  avatarKind: AvatarKind;
  shape: "circle" | "rounded-square";
  background: string;
  foreground: string;
  letter: string | null;
  icon: string | null;
  /** Colour of the unread count and of the time of an unread row. */
  tileLeadingColor: string;
}

/** The drawn avatar of a chat tile, info page and header. */
export function conversationAvatar(convId: string, kind: string, title: string): ConversationAvatar {
  const { seedName, avatarKind } = conversationSpec(convId, kind, title);
  const c = avatarColors(seedName);
  return {
    avatarKind,
    shape: avatarKind === "person" ? "circle" : "rounded-square",
    background: c.background,
    foreground: c.foreground,
    letter: avatarKind === "person" ? personLetter(seedName) : null,
    icon:
      avatarKind === "ticket"
        ? "assets/icons/home/ticket.png"
        : avatarKind === "group"
          ? "assets/icons/home/group.png"
          : null,
    tileLeadingColor: paletteIndex(seedName) < 0 ? PRIMARY_BRIGHT : c.foreground,
  };
}
