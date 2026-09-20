#!/bin/bash
# G2: never send secrets or API keys in a prompt to an external LLM API.
#
# Coverage extended 4.8.2026. The host list used to cover only OpenAI, xAI, OpenRouter, Vertex and
# AI Studio — measured by BEHAVIOUR (not by grepping this file), a secret sent to api.z.ai,
# api.anthropic.com or api.deepseek.com went through untouched. z.ai matters in particular:
# GLM-5.2 is an active member of the T3 review panel.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only commands that call an external LLM API. Comment lines are stripped first — a host named in
# a comment is not a call.
STRIPPED=$(echo "$COMMAND" | grep -v '^[[:space:]]*#')

LLM_HOSTS='api\.openai\.com|api\.x\.ai|openrouter\.ai|aiplatform\.googleapis\.com'
LLM_HOSTS="$LLM_HOSTS"'|generativelanguage\.googleapis\.com|api\.z\.ai|api\.anthropic\.com'
LLM_HOSTS="$LLM_HOSTS"'|api\.deepseek\.com|api\.groq\.com|api\.mistral\.ai|api\.cohere\.com'
LLM_HOSTS="$LLM_HOSTS"'|api\.together\.xyz|api\.cerebras\.ai|api\.siliconflow\.com|api\.perplexity\.ai'

echo "$STRIPPED" | grep -qE "($LLM_HOSTS)" || exit 0

# Search the WHOLE command — a secret can sit in a heredoc, a variable or a JSON body.
SECRETS_FOUND=$(echo "$STRIPPED" | grep -oiE '(REGISTER_SECRET|APNS_KEY|APNS_PROD|LOGS_API_KEY|ADMIN_API_KEY|SYNC_PEPPER|GROQ_API_KEY|REPORT_WEBHOOK|storePassword|keyPassword|private_key.*BEGIN)' | head -3)

if [[ -n "$SECRETS_FOUND" ]]; then
  echo "BLOCKED: secrets found in an LLM prompt." >&2
  echo "Found: $SECRETS_FOUND" >&2
  echo "See skill dev-flow — pre-send sanitisation." >&2
  exit 2
fi

# Absolute paths leak the username and the machine layout. Warning only.
if echo "$STRIPPED" | grep -qE 'content.*(/Users/[a-zA-Z]+/)' 2>/dev/null; then
  echo "WARNING: the prompt contains an absolute /Users/... path — consider a relative one." >&2
fi

exit 0
