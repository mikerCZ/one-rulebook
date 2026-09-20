#!/bin/bash
# G3: conventional commit messages — feat|fix|refactor|chore|docs|test|style|build|ci|perf.
# Blocks a git commit without a valid prefix.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

echo "$COMMAND" | grep -qE 'git\s+commit' || exit 0

# Extract the message. macOS grep has no -P (PCRE) — verified 4.8.2026, /usr/bin/grep -P fails —
# so sed does the capture instead.

# form 1: -m "message"
MSG=$(echo "$COMMAND" | sed -n 's/.*-m "\([^"]*\)".*/\1/p' | head -1)

# form 2: -m 'message'
if [[ -z "$MSG" ]]; then
  MSG=$(echo "$COMMAND" | sed -n "s/.*-m '\([^']*\)'.*/\1/p" | head -1)
fi

# form 3: heredoc — take the first line that already starts with a conventional prefix
if [[ -z "$MSG" ]]; then
  MSG=$(echo "$COMMAND" | grep -oE '^\s*(feat|fix|refactor|chore|docs|test|style|build|ci|perf)(\([^)]+\))?:.*' | head -1 | sed 's/^[[:space:]]*//')
fi

# Could not extract anything — some other format, do not guess.
[[ -z "$MSG" ]] && exit 0

MSG=$(echo "$MSG" | sed 's/^[[:space:]]*//')

if ! echo "$MSG" | grep -qE '^(feat|fix|refactor|chore|docs|test|style|build|ci|perf)(\(.+\))?:\s'; then
  echo "BLOCKED: a commit message must start with a conventional prefix." >&2
  echo "Allowed: feat: | fix: | refactor: | chore: | docs: | test: | style: | build: | ci: | perf:" >&2
  echo "Example: feat: add CarPlay voice search" >&2
  echo "Yours:   $MSG" >&2
  exit 2
fi

exit 0
