#!/bin/bash
# G4: every project must carry a CHANGELOG.md — checked before git push.
#
# The repo root is resolved from the tool call's cwd, falling back to the hook's own working
# directory. A push issued from outside a repo is not guarded — that is a scope limit, not a
# guarantee.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

echo "$COMMAND" | grep -qE 'git\s+push' || exit 0

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -n "$CWD" ] && cd "$CWD" 2>/dev/null

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[[ -z "$PROJECT_ROOT" ]] && exit 0   # not a git repo, nothing to check

if [[ ! -f "$PROJECT_ROOT/CHANGELOG.md" ]]; then
  echo "BLOCKED: CHANGELOG.md does not exist in $PROJECT_ROOT" >&2
  echo "Every project must have one — see ~/.claude/CLAUDE.md, Workflow section." >&2
  exit 2
fi

exit 0
