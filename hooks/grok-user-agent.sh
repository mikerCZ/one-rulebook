#!/bin/bash
# G7: the xAI Grok API requires a User-Agent header — without one Cloudflare 1010 blocks you.
#
# Fixed 4.8.2026: the host match used to fire on any MENTION of the host anywhere in the command,
# including inside a comment. It blocked an analysis command that merely listed the hostname in a
# loop and never called it. Comment lines are now stripped before matching — the guard is about a
# call, not about the string appearing.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# A git commit message is prose, not an invocation — see the same guard in rsync-no-delete.sh.
echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git\s+commit\b' && exit 0

STRIPPED=$(echo "$COMMAND" | grep -v '^[[:space:]]*#')
echo "$STRIPPED" | grep -qE 'api\.x\.ai' || exit 0

if ! echo "$STRIPPED" | grep -qiE '(\-A\s|User-Agent)'; then
  echo "BLOCKED: a call to the xAI API without a User-Agent header." >&2
  echo "Cloudflare 1010 blocks the default Python/curl UA." >&2
  echo "Add: -A \"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36\"" >&2
  echo "See skill llm-apis -> references/xai-grok.md" >&2
  exit 2
fi

exit 0
