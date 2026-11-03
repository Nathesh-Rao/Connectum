# Message formatting (line breaks, lists, bold, links, code)

Written 2 November 2026. A message is still plain text on the wire and in the database: **nothing changed on the server or in any API**. What changed is how the apps **write** and **draw** that text. Code: `chat-app/features/connectumChat/utils/messageFormat.js` (the rules), `formatEdit.js` (what the buttons do), `useFormatting.js` (buttons and keys), `components/MessageText.jsx` (drawing), `FormatToolbar.jsx` (the row of buttons), `RichComposer.jsx` (the rich editor card), `richDom.js` (editor <-> message text), `codeLanguages.js` (the language list), `richEdit.js` (highlight, colour, size, code, quote, link and Enter in the editor).

## Why this exists

A person who typed a list, or pressed Shift+Enter and indented a line, saw it arrive as **one paragraph**. The text was never altered (the server keeps every line break, tab and blank line exactly; `connectum_multiline_test.mjs` proves it for sending, live delivery, history, the conversation list, replies, edits, groups and end-to-end messages). The app drew it with ordinary white-space rules, which squash line breaks. Now it is drawn as written, and it can be formatted.

## The syntax (a small Markdown, the one people know from Teams, Slack and WhatsApp)

| Type | You get | Notes |
|---|---|---|
| `**bold**` | **bold** | |
| `*italic*` or `_italic_` | *italic* | `_` never works inside a word (`snake_case_names` stays as it is) |
| `~~strike~~` | ~~strike~~ | |
| `++underline++` | underlined | like `_`, it never starts inside a word (`C++` stays as it is) |
| `==highlight==` | highlighted | same rule (`a==b` stays as it is) |
| `[color=red]words[/color]` | coloured words | only `red orange yellow green teal blue purple pink gray`; any other name is just text |
| `[size=large]words[/size]` | bigger or smaller words | only `small large huge`; any other name is just text |
| `` `code` `` | `code` | nothing inside is formatted; ``` `` a ` b `` ``` holds a backtick |
| ```` ```js ... ``` ```` | a code block | line breaks and indentation kept, never re-wrapped; the block must be closed, otherwise it is just text |
| `> quote` | a quote | consecutive lines are one quote; lists and paragraphs can be inside |
| `- item`, `* item`, `• item` | a bullet list | |
| `1. item`, `1) item` | a numbered list | the numbers shown are the ones typed |
| two spaces (or a tab) deeper | a nested list | a number list inside a bullet is nested; a number straight after a bullet at the same level starts a new list |
| `[words](https://address)` | a link | `http`, `https` and `mailto` only |
| `https://address` | a link | the full stop or bracket after it is not part of the address |
| `\*` | a star | a backslash makes the next symbol plain |

**Always true:** line breaks, blank lines (up to three kept) and indentation are shown as typed. Anything unclosed or unclear (`**abc`, `a * b * c`, `[x](javascript:...)`) is **just text**: a message never fails to show. **No HTML is ever produced**: what a sender types as `<b>` or `<script>` is shown as those characters, and `javascript:`, `data:` and `file:` links are never links. A text longer than 20,000 characters is shown as it is (no parsing); markers look at most 4,000 characters ahead and quotes nest at most 4 deep, so no message can slow the app down.

**Not supported on purpose:** headings, tables, images, and raw HTML. Colour and size are **names from a fixed list, never a style**: the app draws a name as a CSS class, so a text can not carry a colour code, a font or any CSS of its own (`[color=#ff0000]`, `[color=red;x:y]` and `[size=99]` are shown as typed).

## Writing (the web app)

- In the simple message box **Enter** sends and **Shift+Enter** is a new line: a plain one (the box has no formatting button and no formatting keys; marks can be typed by hand, `**word**`, and are applied when the message is shown). The rich editor (below) and the **Edit message** window have the formatting.
- Keys in the rich editor and the Edit message window (Ctrl on Windows and Linux, ⌘ on a Mac): **B** bold, **I** italic, **K** link, **E** code, **Shift+X** strikethrough, **Shift+7** numbered list, **Shift+8** bulleted list, **Shift+.** quote. The tooltips say so.
- The **Edit message** window has a row of buttons: bold, italic, strikethrough, code, bulleted list, numbered list, quote, code block, link. They work on the selection (or insert an empty pair with the cursor inside), and pressing again undoes. (Earlier the simple message box had the same row behind an **A** button; it was taken out when the rich editor came.)
- **The rich editor** (the button next to the microphone) makes the message box itself grow, as in Teams: the formatting row on top, a taller typing area, and the box's own buttons (attach, emoji, back to the simple box, send) in a row at the bottom right. The message is shown where the message is shown the way it will look: bold is bold, a list is a list, code is in a code box, a link is a link, and no marks (`**`, `[color=..]`) are ever visible. It has bold, italic, underline, strikethrough, bullets and numbers, highlight, font colour (9 names), font size (small, large, huge), quote, link and **code block**, and the buttons light up for what is under the cursor. Behind the scenes the content is kept as the ordinary message text (`utils/richDom.js` turns the editor into text and back after every change), so what is sent, stored and shown is the same text as always and the mobile app needs nothing new. The editor and the simple box share one text (back in the simple box the text shows with its marks, which is what that box is). **Enter** is a new line (it continues a list; a second Enter leaves a list, a quote or a code box), **Ctrl/⌘+Enter** sends, the bin empties the message, the editor button at the bottom (or Escape) goes back to the simple box. The `<>` button inserts a code block like Teams': a header with the language (a list: Plain Text, Bash, C, C++, C#, CSS, Dart, DockerFile, DOS, Go, GraphQL, HTML, Java, JavaScript, JSON, Kotlin, Markdown, PHP, PowerShell, Python, Ruby, Rust, SQL, Swift, TypeScript, XML, YAML), a "..." menu (Copy code, Delete code block), a column of line numbers, and the code, **coloured as it is typed**. The language is written after the three backticks (` ```javascript `) and shown as a small name above the code in the message; the header and the numbers are never part of the message text. Backspace at the start of an empty code box turns it back into a line. Keys: **Ctrl/⌘+B / I / U** (the browser's own), **K** link, **E** inline code (no button: a pair of backticks round some words), **Shift+X** strikethrough, **Shift+H** highlight, **Shift+7 / 8** lists, **Shift+.** quote. Only plain text is taken in when pasting (no styles or markup from another page). What a person types that looks like a mark (`**x**`, `[color=red]`, a line starting with `- `) is escaped, so it stays as typed.
- Typing the marks by hand works the same (`**word**`): the formatting is applied when the message is shown, so "auto formatting" needs nothing special.
- White space at the edge of a selection stays outside the marks (`**word **` would not show as bold). A link button on selected words makes `[words](https://)` with the address selected for typing.

## Where it is shown

The message bubbles (main chat and the small chat), and nowhere else as formatted text. **Previews are one plain line without the marks** (`plainText`): the conversation list, the quote of a reply (in the bubble and above the box), and the small chat's alerts. A file's caption is shown with its line breaks.

## For the mobile app

The wire format did not change, so an app that does nothing still works: it shows the marks as typed. To match the web app:

1. **Draw** messages with the rules above. `docs/message-format-vectors.json` has 38 sample messages with the exact tree the web app makes of each (`blocks`) and the one-line text (`plain`); check your parser against it (it is generated from the engine, and a test fails if the two ever disagree). The tree: block `p` (inline nodes), `quote` (blocks), `list` (`ordered`, `items` with `c` inline and `sub` list), `code` (`lang`, `v`); inline `text`, `b`, `i`, `s`, `u`, `mark`, `color` and `size` (both with `name`), `code`, `a` (`href`). A client that does not know `u`, `mark`, `color` or `size` can show their content (`c`) as plain text.
2. **Keep line breaks and indentation** when sending: send the text as typed. The server trims the **end** of the whole message and keeps everything else (the start too); a message is at most **2,000 characters** (an encrypted one has its own, larger limit). Windows line breaks (`\r\n`) are kept as sent and read the same as `\n`.
3. **Write:** a multi-line input where the keyboard's return key adds a line (or Shift+Enter on a hardware keyboard), and, if you like, a formatting row with the same buttons. `formatEdit.js` has the exact behaviour of each (it is the specification: pure functions with tests).
4. **Previews:** show `plain`, never the marks.
5. **Safety rules to copy:** build the view from the tree (never through HTML), open only `http`, `https` and `mailto` links, show everything else as text.

## Tests

- `tests/frontend/messageFormat.test.mjs` (30): every rule, hostile and pathological input (thousands of unmatched marks, deep nesting, a fuzz run of 3,000 random texts: nothing throws, every link is safe, nothing is slow).
- `tests/frontend/formatEdit.test.mjs` (23): every button and key on every kind of selection.
- `tests/frontend/richDom.test.mjs` (10): the rich editor and the message text, both ways: every sample message shown in the editor and read back looks the same; what a person types is never turned into formatting; markup is only ever text.
- `tests/frontend/richFormat.test.mjs`: underline, highlight, colour and size (parsing, only-listed-names, hostile input, the buttons, the list-sign rule).
- `tests/frontend/messageFormatVectors.test.mjs`: the reference file for the mobile app.
- `connectum-backend/test/connectum_multiline_test.mjs` (16): the server keeps line breaks, tabs, indentation and blank lines on every path, and its limits.
- `tools/ui-audit/message-format.e2e.mjs`: the whole thing in a real browser (typing with Shift+Enter and the buttons and keys, what the sender and the reader see, previews, safety against markup and scripts, dark theme, a narrow window).

## Colours for code, and the look of code everywhere

- **One look for code:** chat messages, AI answers (`features/aiFormat`) and the rich editor draw code the same way: a code block with a header (the language, and a Copy button in messages) on its own light or dark surface, so the colours read on any bubble, and **inline code as a small boxed word** (a white box with a thin border; in the dark theme a light box on a dark one). Files: `components/codeHighlight.css` (the look and the colours), `HighlightedCode.jsx` (the coloured code), `utils/codeHighlight.js` (the cutting), `utils/codeLanguages.js` (the list of languages and their other names: `js`, `py`, `c++`, `yml`, `sh` ...).
- **Languages with colours:** Bash, C, C++, C#, CSS, Dart, DockerFile, DOS, Erlang, Go, GraphQL, HTML, Java, JavaScript, JSON, Kotlin, Markdown, PHP, PowerShell, Python, Ruby, Rust, SQL, Swift, TypeScript, XML, YAML. Plain text, a language that is not on the list, and a text of more than 20,000 characters are shown without colours. The cutting is done by highlight.js (an added dependency; only these languages are loaded).
- **Safe by construction:** highlight.js answers with a string of `<span class="hljs-..">`; it is read back into plain pieces (text and a class name) and drawn as elements, never put into the page as HTML, and the pieces always add up to exactly the code that was written (a test checks it for every language, with hostile input too).
- **Nothing changes on the wire:** the colours are made when a message is shown; the stored text is still `\`\`\`python ... \`\`\``. The mobile app can colour code with its own highlighter by the same language ids.
- Tests: `tests/frontend/codeHighlight.test.mjs` (every language of the list is coloured and gives back the code; the other names work; markup stays text; hostile input is fast).
