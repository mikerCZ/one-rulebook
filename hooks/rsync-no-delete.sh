#!/bin/bash
# G6: a mirroring rsync must carry a seatbelt.
#
# 🔧 REWRITTEN 4.8.2026 — from "ban the delete flag" to "require the protection".
#
# The old rule banned the flag outright. That was fixing the symptom: the thing actually worth
# protecting is "files that exist only on the receiver must survive", and the flag is merely the
# usual way to lose them. The ban also blocked --dry-run, i.e. the one command that lets you
# check safely, and it blocked its own documentation and its own commit message.
#
# Measured 4.8.2026 against a local fixture (a docroot with server-generated statistics dirs):
#   * plain delete           → the server-only statistics dirs WIPED
#   * delete + --exclude     → both SURVIVED, stale pages still removed
#   * delete + --filter=protect → same result, BUT Apple's /usr/bin/rsync (openrsync) REJECTS
#     --filter=protect while accepting --exclude and --max-delete. Use --exclude; it is portable.
#   * --max-delete=0         → rc=25, aborts, deletes nothing
#   * empty source + --max-delete=2 → rc=25, damage capped, the page files survived
#     (a cap limits the damage, it does NOT prevent all of it — it is a seatbelt, not a lock)
#
# So the rule is: a dry run is always fine; a real delete needs --max-delete.
# Which paths to exclude is project knowledge and lives in the project skill, not here.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# A git commit message is prose, not an invocation.
echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git\s+commit\b' && exit 0

STRIPPED=$(echo "$COMMAND" | grep -v '^[[:space:]]*#')
echo "$STRIPPED" | grep -qE '(^|[;&|[:space:]])rsync\b' || exit 0
echo "$STRIPPED" | grep -qE '\-\-delete(-after|-before|-during|-delay)?\b' || exit 0

# A dry run changes nothing and is how you are supposed to check. Always allowed.
echo "$STRIPPED" | grep -qE '\-\-dry-run|(^|[[:space:]])-n([[:space:]]|$)' && exit 0

if ! echo "$STRIPPED" | grep -qE '\-\-max-delete=[0-9]+'; then
  echo "BLOCKED: a mirroring rsync without --max-delete." >&2
  echo "" >&2
  echo "A wrong or empty source path would mirror the emptiness onto the server." >&2
  echo "--max-delete=N aborts (rc=25) instead, capping the damage." >&2
  echo "" >&2
  echo "Do this instead:" >&2
  echo "  1) dry run first — always allowed, changes nothing:" >&2
  echo "     rsync -avz --dry-run --delete-after --exclude=... SRC DST | grep '^deleting'" >&2
  echo "  2) then the real run with a cap and the receiver-only paths excluded:" >&2
  echo "     rsync -avz --delete-after --max-delete=25 --exclude=... SRC DST" >&2
  echo "" >&2
  echo "Server-generated directories (stats/, stats-goaccess/) must be in --exclude —" >&2
  echo "they are in no repo and a mirror wipes them." >&2
  exit 2
fi

exit 0
