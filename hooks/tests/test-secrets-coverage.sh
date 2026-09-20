#!/bin/bash
# Behavioural coverage test for check-secrets-in-llm.sh.
# Kept in a file so the probe strings never appear in a Bash tool command line,
# where the hook under test would block the test itself.
H=~/.claude/hooks/check-secrets-in-llm.sh
SECRET="LOGS_""API_KEY"
for u in "api.openai.com/v1/chat" "openrouter.ai/api/v1" "aiplatform.googleapis.com/v1" \
         "generativelanguage.googleapis.com/v1beta" "api.z.ai/api/paas/v4/chat" \
         "api.anthropic.com/v1/messages" "api.deepseek.com/v1"; do
  host=${u%%/*}
  cmd="curl -s https://$u -d '{\"$SECRET\":\"abc123\"}'"
  rc=$(jq -nc --arg c "$cmd" '{tool_input:{command:$c}}' | $H >/dev/null 2>&1; echo $?)
  if [ "$rc" = "2" ]; then echo "  ✅ $host — secret zachycen"; else echo "  ❌ $host — secret PROJDE (rc=$rc)"; fi
done
