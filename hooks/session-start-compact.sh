#!/bin/bash
# SessionStart (matcher "compact"): after the context was compacted, inject
# (a) freshly measured git state, (b) the pre-compact snapshot taken by
# precompact-snapshot.sh, and (c) instructions to re-verify before acting.
# stdin: hook JSON; stdout: JSON with hookSpecificOutput.additionalContext.
set -u

input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
cwd=$(printf '%s' "$input" | jq -r ".cwd // \"$PWD\"")

dir="$HOME/.claude/compact-snapshots"
snap="$dir/${session_id}.md"
[ -f "$snap" ] || snap="$dir/latest.md"

ctx="Context was just compacted. The summary is derived text, not a measurement — volatile state in it (branch, uncommitted files, in-flight tasks, build or deploy state) is unverified. Re-verify against the sources below before acting on it."
ctx+=$'\n\n'"Fresh state measured now:"
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ctx+=$'\n'"- branch: $(git -C "$cwd" branch --show-current 2>/dev/null)"
  ctx+=$'\n'"- HEAD: $(git -C "$cwd" log -1 --oneline 2>/dev/null)"
  status=$(git -C "$cwd" status --short 2>/dev/null | head -30)
  if [ -n "$status" ]; then
    ctx+=$'\n'"- uncommitted:"$'\n'"$status"
  else
    ctx+=$'\n'"- working tree clean"
  fi
else
  ctx+=$'\n'"- cwd $cwd is not a git repository"
fi

if [ -f "$snap" ]; then
  ctx+=$'\n\n'"Pre-compact snapshot ($snap):"$'\n'"$(cat "$snap")"
fi

ctx+=$'\n\n'"If the summary disagrees with the snapshot or the fresh state, trust the measurement, not the summary. Continue the in-flight task; decisions recorded before the compact stay closed."

jq -n --arg ctx "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
