#!/usr/bin/env bash
# Mirrors the backend docs from origin/dev of the web repo into reference/.
# The web repo is READ-ONLY here: only `git fetch origin dev`, `git log`,
# `git diff`, `git show`, `git ls-tree`, `git rev-parse`, `git merge-base`.
# Never checkout, pull, merge or write there.
#
#   tool/be_sync/sync_be_docs.sh [--dry-run]
#
# Env: WEB_REPO (default ~/Development/Axi-apps), DEV_BASE_URL (optional,
# e.g. http://10.0.2.113: enables the deployed-version check).
set -u

DRY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WEB="${WEB_REPO:-$HOME/Development/Axi-apps}"
STATE="$ROOT/reference/.be-sync-state"
REF=origin/dev
DOCS=connectum/docs
TOOLS=connectum/tools/mobile-test
WATCH="$DOCS $TOOLS connectum/tools/sample-forms connectum/connectum-backend/src/core/sd_cmd*.erl connectum/connectum-backend/src/chat/chat_cmds.erl connectum/connectum-backend/src/chat/chat_web_listener.erl"

g() { git -C "$WEB" "$@"; }
say() { printf '%s\n' "$*"; }
head_() { printf '\n== %s ==\n' "$*"; }

[ -d "$WEB/.git" ] || { say "web repo not found at $WEB (set WEB_REPO)"; exit 1; }
[ "$DRY" = 1 ] && say "DRY RUN: nothing under reference/ will be written."

head_ "fetch"
g fetch origin dev 2>&1 | sed 's/^/  /' || { say "fetch failed"; exit 1; }
NEW="$(g rev-parse "$REF")" || exit 1
NEW_DATE="$(g log -1 --format=%cs "$REF")"
say "  $REF = ${NEW:0:10} ($NEW_DATE)"

LAST=""
if [ -f "$STATE" ]; then
  LAST="$(sed -n 's/^sha=//p' "$STATE" | head -1)"
  say "  last synced: ${LAST:0:10} ($(sed -n 's/^date=//p' "$STATE" | head -1))"
fi
if [ -n "$LAST" ] && ! g cat-file -e "$LAST^{commit}" 2>/dev/null; then
  say "  last synced commit is not in the repo any more: treating as a first run"
  LAST=""
fi

head_ "commits touching docs, tools and the API/command handlers"
if [ -z "$LAST" ]; then
  say "  no usable state: first run, no commit range. Files are compared by content below."
elif [ "$LAST" = "$NEW" ]; then
  say "  none (already at $REF)"
else
  # shellcheck disable=SC2086
  g log --format='  %h %cs %s' "$LAST..$REF" -- $WATCH
  say "  files:"
  # shellcheck disable=SC2086
  g diff --name-status "$LAST" "$REF" -- $WATCH | sed 's/^/    /'
fi

# --- what we mirror ---------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
g ls-tree --name-only "$REF" "$DOCS/" > "$TMP/docs.txt"       # top level of docs
g ls-tree --name-only "$REF" "$TOOLS/" > "$TMP/tools.txt"

# local file <TAB> upstream path. Same basename as a top-level docs file,
# outside the pinned packs and the prototype; test-env/tools <- tools/mobile-test.
: > "$TMP/map.txt"
while IFS= read -r f; do
  base="$(basename "$f")"
  up="$(grep "/$base\$" "$TMP/docs.txt" | head -1)"
  [ -n "$up" ] && printf '%s\t%s\n' "$f" "$up" >> "$TMP/map.txt"
done < <(cd "$ROOT" && find reference -type f \
  -not -path 'reference/prototype/*' -not -path 'reference/screenshots/*' \
  -not -path 'reference/backend-pack/*' -not -path 'reference/test-env/tools/*' \
  -not -name '.DS_Store')
while IFS= read -r f; do
  base="$(basename "$f")"
  up="$(grep "/$base\$" "$TMP/tools.txt" | head -1)"
  [ -n "$up" ] && printf '%s\t%s\n' "$f" "$up" >> "$TMP/map.txt"
done < <(cd "$ROOT" && find reference/test-env/tools -type f -not -name '.DS_Store' 2>/dev/null)

head_ "mirrored files that differ from $REF"
: > "$TMP/changed.txt"
while IFS=$'\t' read -r local up; do
  if ! g show "$REF:$up" 2>/dev/null | cmp -s - "$ROOT/$local"; then
    printf '%s\t%s\n' "$local" "$up" >> "$TMP/changed.txt"
    add=$(g show "$REF:$up" | diff "$ROOT/$local" - | grep -c '^>')
    del=$(g show "$REF:$up" | diff "$ROOT/$local" - | grep -c '^<')
    say "  $local  (+$add -$del lines)  <- $up"
  fi
done < "$TMP/map.txt"
[ -s "$TMP/changed.txt" ] || say "  none: $(wc -l < "$TMP/map.txt" | tr -d ' ') mirrored files are up to date"

# --- new docs ---------------------------------------------------------------
head_ "new docs"
: > "$TMP/newcopy.txt"
: > "$TMP/newother.txt"
if [ -n "$LAST" ] && [ "$LAST" != "$NEW" ]; then
  g diff --name-only --diff-filter=A "$LAST" "$REF" -- "$DOCS" \
    | grep -E "^$DOCS/[^/]+$" > "$TMP/added.txt" || true
  while IFS= read -r up; do
    [ -n "$up" ] || continue
    base="$(basename "$up")"
    if [ -n "$(cd "$ROOT" && find reference -name "$base" -not -path 'reference/backend-pack/*' | head -1)" ]; then continue; fi
    case "$base" in
      MOBILE*|PRIVATE_AI*|LOGIN*) printf 'reference/%s\t%s\n' "$base" "$up" >> "$TMP/newcopy.txt" ;;
      *) echo "$up" >> "$TMP/newother.txt" ;;
    esac
  done < "$TMP/added.txt"
  if [ -s "$TMP/newcopy.txt" ]; then
    say "  will be copied (MOBILE*, PRIVATE_AI*, LOGIN*):"; cut -f2 "$TMP/newcopy.txt" | sed 's/^/    /'
  else say "  none to copy"; fi
  if [ -s "$TMP/newother.txt" ]; then
    say "  other new docs (NOT copied, tell the team if relevant):"; sed 's/^/    /' "$TMP/newother.txt"
  fi
else
  say "  not known without a previous sync (or nothing new)."
  # top-level MOBILE*/PRIVATE_AI*/LOGIN* docs we do not hold yet, by basename
  while IFS= read -r up; do
    base="$(basename "$up")"
    case "$base" in MOBILE*|PRIVATE_AI*|LOGIN*) ;; *) continue ;; esac
    if [ -z "$(cd "$ROOT" && find reference -name "$base" -not -path 'reference/backend-pack/*' | head -1)" ]; then
      printf 'reference/%s\t%s\n' "$base" "$up" >> "$TMP/newcopy.txt"
    fi
  done < "$TMP/docs.txt"
  if [ -s "$TMP/newcopy.txt" ]; then
    say "  matching MOBILE*/PRIVATE_AI*/LOGIN* that reference/ does not hold by that name (would be copied):"
    cut -f2 "$TMP/newcopy.txt" | sed 's/^/    /'
  fi
fi

# --- deployed version check -------------------------------------------------
head_ "deployed dev release"
if [ -z "${DEV_BASE_URL:-}" ]; then
  say "  DEV_BASE_URL not set: skipped."
else
  BODY="$(curl -fsS --max-time 5 "${DEV_BASE_URL%/}/api/sd/version" 2>/dev/null || true)"
  if [ -z "$BODY" ]; then
    say "  $DEV_BASE_URL unreachable (VPN?): skipped, continuing."
  else
    REL="$(printf '%s' "$BODY" | sed -n 's/.*"release"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    ENVN="$(printf '%s' "$BODY" | sed -n 's/.*"environment"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    DOCSHA="$(g rev-parse --short=7 "$REF")"
    say "  environment=$ENVN release=$REL"
    if [ "$ENVN" != "dev" ]; then
      say "  WARNING: this is not a dev instance."
    elif [ -z "$REL" ]; then
      say "  no release in the answer."
    elif [ "${NEW#$REL}" != "$NEW" ]; then
      say "  docs match the deployed dev release"
    elif ! g cat-file -e "$REL^{commit}" 2>/dev/null; then
      say "  deployed release $REL is not in origin/dev (not fetched yet, or built elsewhere): cannot compare"
    elif g merge-base --is-ancestor "$REL" "$REF"; then
      say "  docs are AHEAD of the deployed dev (deployed $REL, docs $DOCSHA)"
    elif g merge-base --is-ancestor "$REF" "$REL"; then
      say "  docs are BEHIND the deployed dev (deployed $REL, docs $DOCSHA)"
    else
      say "  docs and deployed dev have diverged (deployed $REL, docs $DOCSHA)"
    fi
  fi
fi

# --- apply ------------------------------------------------------------------
head_ "apply"
if [ "$DRY" = 1 ]; then
  n=$(cat "$TMP/changed.txt" "$TMP/newcopy.txt" | wc -l | tr -d ' ')
  say "  dry run: would update $n file(s) and write $STATE (sha ${NEW:0:10}, date $NEW_DATE)."
  exit 0
fi
cat "$TMP/changed.txt" "$TMP/newcopy.txt" | while IFS=$'\t' read -r local up; do
  [ -n "$local" ] || continue
  mkdir -p "$(dirname "$ROOT/$local")"
  g show "$REF:$up" > "$ROOT/$local"
  say "  wrote $local"
done
printf 'sha=%s\ndate=%s\n' "$NEW" "$NEW_DATE" > "$STATE"
say "  state: ${NEW:0:10} ($NEW_DATE) -> reference/.be-sync-state"
