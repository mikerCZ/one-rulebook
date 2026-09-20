#!/bin/bash
# G8: prefer Vertex AI for Gemini; AI Studio has outages.
#
# ⚠️ This hook WARNS, it does not block — AI Studio is a legitimate emergency fallback.
# The header used to read "ALWAYS Vertex AI, NEVER AI Studio", which overstated what the code
# actually does (corrected 4.8.2026).

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if echo "$COMMAND" | grep -qE 'generativelanguage\.googleapis\.com'; then
  echo "WARNING: you are using the AI Studio endpoint for Gemini." >&2
  echo "Prefer Vertex AI (aiplatform.googleapis.com) — more stable, no outages." >&2
  echo "AI Studio is an emergency fallback only." >&2
  echo "See skill llm-apis -> references/gemini-vertex.md" >&2
fi

exit 0
