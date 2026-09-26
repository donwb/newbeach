#!/bin/bash
# Stop hook (ATC status contract, schema 2). Once per session: if commits landed after
# PORTFOLIO-STATUS.md was last committed, on a later day than its last_verified, ask the
# agent to update it or say why nothing status-relevant changed. Never blocks twice.
input=$(cat)
printf '%s' "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0
sid=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
marker="${TMPDIR:-/tmp}/atc-status-guard-${sid:-nosession}"
[ -e "$marker" ] && exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
f=PORTFOLIO-STATUS.md
[ -f "$f" ] || exit 0
git diff --quiet HEAD -- "$f" 2>/dev/null || exit 0      # already being edited: fine
touched=$(git log -1 --format=%H -- "$f" 2>/dev/null) || exit 0
[ -n "$touched" ] || exit 0
n=$(git rev-list --count "$touched"..HEAD 2>/dev/null) || exit 0
[ "$n" -gt 0 ] || exit 0
last_day=$(git log -1 --format=%cs)
lv=$(grep -m1 '^last_verified:' "$f" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
[[ "$last_day" > "${lv:-0000-00-00}" ]] || exit 0

touch "$marker"
printf '{"decision":"block","reason":"%s"}\n' \
  "ATC status check: $n commit(s) since PORTFOLIO-STATUS.md was last updated (last_verified ${lv:-missing}, last commit $last_day). If this session changed anything status-relevant, update the schema-2 header, bump last_verified, and add a STATUS-LOG.md entry. Otherwise reply in one line saying why nothing status-relevant changed."
