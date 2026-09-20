#!/bin/bash
# Read the authoritative Claude Code plan usage — the same data `/usage` shows.
#
#   claude-usage.sh [THRESHOLD]      # THRESHOLD = utilization %% at which to stop (default 95)
#
# Exit codes (same convention as codex-quota.sh):
#   0  below threshold — safe to start another step
#   1  at or above threshold on the 5-hour OR the 7-day window — pause
#   2  no reading (no token, network down, unexpected payload) — decide manually
#
# Why this exists: an agent working through a multi-step plan needs to stop at a
# checkpoint BEFORE the limit hits, not discover it mid-edit. `ccusage` cannot
# answer this — it infers a ceiling from the highest usage seen in previous
# blocks, which is an estimate, not the quota.
#
# ⚠️ The 7-day window is checked too. Waiting out a 5-hour reset does nothing if
# the weekly limit is what ran out — the reset timestamps differ by days.

set -uo pipefail

THRESHOLD=${1:-95}

# Profile-aware: reads the quota of the account the CALLING session is logged in
# as. Claude Code keys the Keychain entry to CLAUDE_CONFIG_DIR with the first 8
# hex of sha256(config dir) — `Claude Code-credentials-<profile-hash>` (verified 5.9.2026:
# `printf %s <the profile dir> | shasum -a 256` reproduces the suffix of the second profile's entry).
CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    KEYCHAIN_SVC="Claude Code-credentials-$(printf '%s' "$CLAUDE_CONFIG_DIR" | shasum -a 256 | cut -c1-8)"
else
    KEYCHAIN_SVC="Claude Code-credentials"
fi
CACHE="$CFG_DIR/cache/oauth-usage.json"
TTL=60

fetch() {
    local token
    token=$(security find-generic-password -s "$KEYCHAIN_SVC" -w 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" 2>/dev/null)
    [ -z "$token" ] && return 1
    mkdir -p "$(dirname "$CACHE")"
    curl -s -m 5 "https://api.anthropic.com/api/oauth/usage" \
        -H "Authorization: Bearer $token" \
        -o "$CACHE.tmp" 2>/dev/null || { rm -f "$CACHE.tmp"; return 1; }
    # Reject rate-limit / auth-error JSON: a body without a numeric
    # five_hour.utilization is not a reading, and must not overwrite a good cache.
    if jq -e '.five_hour.utilization | numbers' "$CACHE.tmp" >/dev/null 2>&1; then
        mv "$CACHE.tmp" "$CACHE"
    else
        rm -f "$CACHE.tmp"; return 1
    fi
}

age=999999
[ -f "$CACHE" ] && age=$(( $(date +%s) - $(stat -f %m "$CACHE" 2>/dev/null || echo 0) ))
[ "$age" -gt "$TTL" ] && fetch

if [ ! -f "$CACHE" ] || ! jq -e '.five_hour.utilization | numbers' "$CACHE" >/dev/null 2>&1; then
    echo "usage: NO READING (no token / network / unexpected payload)"
    exit 2
fi

age=$(( $(date +%s) - $(stat -f %m "$CACHE" 2>/dev/null || echo 0) ))

# Read the `limits` ARRAY, not the two named top-level fields. There are more
# windows than five_hour + seven_day: a model-scoped weekly bucket appears as
# kind="weekly_scoped" (that is the one Fable burns — /usage labels it
# "Current week (Fable)"), and it is invisible in five_hour/seven_day. Iterating
# the array also survives new buckets appearing without a script change.
# Falls back to the two named fields if `limits` is absent.
if jq -e '.limits | arrays and length > 0' "$CACHE" >/dev/null 2>&1; then
    jq -r '.limits[] | "\(.kind)\t\(.percent)\t\(.resets_at // "?")"' "$CACHE" \
      | while IFS=$'\t' read -r kind pct reset; do
            printf '%-14s %3s%% (remaining %s%%, resets %s)\n' "$kind" "$pct" "$((100 - pct))" "$reset"
        done
    worst_kind=$(jq -r '[.limits[]] | max_by(.percent) | .kind' "$CACHE")
    worst=$(jq -r '[.limits[].percent] | max' "$CACHE")
else
    fh=$(jq -r '.five_hour.utilization | floor' "$CACHE")
    sd=$(jq -r '.seven_day.utilization | floor' "$CACHE")
    printf 'session        %3s%%\nweekly_all     %3s%%\n' "$fh" "$sd"
    if [ "$fh" -ge "$sd" ]; then worst=$fh; worst_kind=session; else worst=$sd; worst_kind=weekly_all; fi
fi

printf 'reading age: %ss · threshold: %s%% · highest: %s at %s%%\n' \
       "$age" "$THRESHOLD" "$worst_kind" "$worst"

if [ "$worst" -ge "$THRESHOLD" ]; then
    echo "VERDICT: PAUSE ($worst_kind) — commit the current step and stop at a checkpoint."
    exit 1
fi
echo "VERDICT: OK to continue."
exit 0
