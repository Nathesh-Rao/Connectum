// node --experimental-strip-types tokens/avatar-color.test.ts   (Node 22.6+)
import { readFileSync } from "node:fs";
import { avatarColors, conversationAvatar, paletteIndex, personLetter, plainInitials, senderInk } from "./avatar-color.ts";

const v = JSON.parse(readFileSync(new URL("./avatar-color-vectors.json", import.meta.url), "utf8"));
let checks = 0;
const failures: string[] = [];
const eq = (what: string, got: unknown, want: unknown) => {
  checks++;
  if (got !== want) failures.push(`${what}: got ${JSON.stringify(got)} want ${JSON.stringify(want)}`);
};

for (const n of v.names) {
  const c = avatarColors(n.input);
  const tag = JSON.stringify(n.input).slice(0, 40);
  eq(`index ${tag}`, paletteIndex(n.input), n.paletteIndex);
  eq(`foreground ${tag}`, c.foreground, n.foreground);
  eq(`background ${tag}`, c.background, n.background);
  eq(`personLetter ${tag}`, personLetter(n.input), n.personLetter);
  eq(`plainInitials ${tag}`, plainInitials(n.input), n.plainInitials);
  eq(`tileLeadingColor ${tag}`, conversationAvatar("group:x", "group", n.input).tileLeadingColor, n.tileLeadingColor);
}
for (const c of v.conversations) {
  const a = conversationAvatar(c.convId, c.kind, c.title);
  const tag = `${c.convId} / ${JSON.stringify(c.title)}`;
  eq(`avatarKind ${tag}`, a.avatarKind, c.avatarKind);
  eq(`background ${tag}`, a.background, c.drawnBackground);
  eq(`shape ${tag}`, a.shape, c.drawnShape);
  eq(`letter ${tag}`, a.letter, c.drawnLetter ?? null);
  eq(`icon ${tag}`, a.icon, c.icon);
}
for (const s of v.senderInk) eq(`senderInk ${JSON.stringify(s.sender).slice(0, 40)}`, senderInk(s.sender), s.color);

console.log(`${checks} checks, ${failures.length} failures`);
for (const f of failures) console.log("FAIL", f);
process.exit(failures.length ? 1 : 0);
