#!/bin/bash
# G5: never run two xcodebuild processes in parallel — they share DerivedData and build.db
# ("database is locked").
#
# 🔴 FIXED 4.8.2026 — this hook was DEAD.
# It used to test for a lock file at /tmp/xcodebuild.claude.lock and block when the PID inside was
# alive. Nothing anywhere ever created that file (verified 4.8.2026: 0 writers across ~/.claude
# and the project repo), so the test could not come true and the hook could not block anything. It watched
# for the PRESENCE OF A PROXY that nothing produced, instead of the effect it cares about.
#
# It now asks the only question that matters: is an xcodebuild running right now?
#
# What was verified (4.8.2026) and what was not:
#   ✔ the blocking branch executes and returns 2 — seen red by mutating the pgrep target to a
#     process that was genuinely running (a backgrounded `sleep`), not merely assumed
#   ✔ `pgrep -x` matches a binary invoked from PATH (/bin/sleep → comm "sleep")
#   ✔ verified against a REAL xcodebuild on 5.9.2026: one `xcodebuild -list -project
#     <Project>.xcodeproj` was started in the background, `pgrep -x xcodebuild` matched it while it
#     ran, and this hook returned 2 naming that pid; the same input returned 0 once it had exited.
#     That closes the inference the previous note left open (comm is "xcodebuild", so -x matches).
#
# For contrast, the version that ran in Codex until that day tested for a lock file at
# /tmp/xcodebuild.claude.lock. Nothing has ever created it (checked 5.9.2026: the file does not
# exist, and a grep over ~/.claude, ~/.codex and the project repo that day returned this comment
# and old session transcripts, no writer), so
# that hook could not block anything.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Ignore comment lines — a mention of xcodebuild in a comment is not an invocation.
STRIPPED=$(echo "$COMMAND" | grep -v '^[[:space:]]*#')
echo "$STRIPPED" | grep -qE '(^|[;&|[:space:]])xcodebuild\b' || exit 0

# Our own PID subtree must not count itself.
RUNNING=$(pgrep -x xcodebuild 2>/dev/null | head -5)

if [[ -n "$RUNNING" ]]; then
  echo "BLOCKED: an xcodebuild is already running (PID $(echo $RUNNING | tr '\n' ' '))." >&2
  echo "Never run two in parallel — they share the DerivedData / build.db lock." >&2
  echo "Wait for it to finish, or check with: pgrep -lx xcodebuild" >&2
  exit 2
fi

exit 0
