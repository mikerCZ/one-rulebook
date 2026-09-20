#!/bin/bash
# Claude Code 3-line status line.
#
# Line 1: {project} · {model}
# Line 2: {color-graded bar} {pct}% · {used_tokens}/{total_tokens}
# Line 3: session N% (Xm) · week N% (DAY HH:MM) · fable N% (Xh Ym) · sonnet N%
#         (5-hour block + 7-day all-models + 7-day model-scoped [Fable] + 7-day Sonnet, source: same data
#          the /usage slash command shows)
#
# Colors escalate based on fill (same scale for context + plan-usage):
#   < 60%   green    (plenty of room)
#   60-74%  white    (mid)
#   75-89%  yellow   (warning — plan for compaction)
#   >= 90%  red      (urgent — near limit)
#
# No token cost — lines 1-2 read from stdin JSON only.
# Line 3 hits api.anthropic.com/api/oauth/usage (OAuth scope, doesn't bill),
# cached 60s with background refresh so warm renders are ~150 ms.
# First-ever invocation shows lines 1-2 only until bg fetch lands.

input=$(cat)

# --- Extract fields (all with fallbacks so empty early-session state renders cleanly) ---
model=$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // "claude"' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // ""' 2>/dev/null)

if [ -z "$cwd" ] || [ "$cwd" = "$HOME" ]; then
    project="~"
else
    project=$(basename "$cwd")
fi

# Use used_percentage + context_window_size as the source of truth.
# We deliberately do NOT use total_input_tokens because that field is
# CUMULATIVE input across all API calls in the session (includes cache hits
# and repeated sends), which wildly under- or over-shoots the current
# context fill. Deriving used = pct × total / 100 keeps the two displayed
# numbers always internally consistent.
pct=$(printf '%s' "$input" | jq -r '(.context_window.used_percentage // 0) | floor' 2>/dev/null)
total=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // 200000' 2>/dev/null)

# Guard against jq returning empty/non-numeric
[[ "$pct" =~ ^[0-9]+$ ]] || pct=0
[[ "$total" =~ ^[0-9]+$ ]] || total=200000

# Derive absolute used tokens from percentage (source-of-truth consistency)
used=$((pct * total / 100))

# --- Format tokens as human-readable (526k, 1.0M) ---
fmt() {
    local n=$1
    if [ "$n" -ge 1000000 ]; then
        awk -v n="$n" 'BEGIN { printf "%.1fM", n/1000000 }'
    elif [ "$n" -ge 1000 ]; then
        echo "$((n / 1000))k"
    else
        echo "$n"
    fi
}
used_fmt=$(fmt "$used")
total_fmt=$(fmt "$total")

# --- Progress bar (20 chars wide) ---
BAR_WIDTH=20
filled=$((pct * BAR_WIDTH / 100))
[ $filled -gt $BAR_WIDTH ] && filled=$BAR_WIDTH
[ $filled -lt 0 ] && filled=0
empty=$((BAR_WIDTH - filled))

bar=""
i=0; while [ $i -lt $filled ]; do bar="${bar}▓"; i=$((i+1)); done
i=0; while [ $i -lt $empty ]; do bar="${bar}░"; i=$((i+1)); done

# --- ANSI colors based on fill threshold ---
reset=$'\e[0m'
dim=$'\e[2m'
cyan=$'\e[36m'
if [ "$pct" -ge 90 ]; then
    bar_color=$'\e[31m'   # red — urgent
elif [ "$pct" -ge 75 ]; then
    bar_color=$'\e[33m'   # yellow — warning
elif [ "$pct" -ge 60 ]; then
    bar_color=$'\e[37m'   # white — mid
else
    bar_color=$'\e[32m'   # green — plenty
fi

# --- Plan-usage cache (5h block / 7-day all models / 7-day Sonnet) ---
# Source: api.anthropic.com/api/oauth/usage (same data the /usage slash command
# shows). 60s file cache with background refresh — the call takes ~380 ms cold
# so we never block the statusline render on it. First-ever invocation shows
# context-only output until the bg fetch lands; every subsequent render reads
# the cache file directly (measured 5.9.2026: 75 ms per warm render, of which
# ~7 ms is the jq that reads the account e-mail out of .claude.json; the rest is
# the other jq/python3 spawns this script already made).
# Profile-aware: every CLAUDE_CONFIG_DIR is a separate login with its own quota,
# so both the cache file and the Keychain entry have to be keyed to it. Claude Code
# suffixes the Keychain service with the first 8 hex of sha256(config dir)
# (verified 5.9.2026: `printf %s <that profile's absolute path> | shasum -a 256` reproduces the
# suffix of the second profile's entry, `Claude Code-credentials-<profile-hash>`).
CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ -n "$CLAUDE_CONFIG_DIR" ]; then
    KEYCHAIN_SVC="Claude Code-credentials-$(printf '%s' "$CLAUDE_CONFIG_DIR" | shasum -a 256 | cut -c1-8)"
else
    KEYCHAIN_SVC="Claude Code-credentials"
fi
# Tag + logged-in e-mail shown on line 3, so the numbers are never read against
# the wrong account. The e-mail lives in .claude.json — inside the config dir for
# a custom CLAUDE_CONFIG_DIR, at ~/.claude.json for the default profile
# (measured 5.9.2026: ~/.claude/.claude.json does not exist).
PROFILE_TAG=""
[ "$CFG_DIR" != "$HOME/.claude" ] && PROFILE_TAG=$(basename "$CFG_DIR" | sed 's/^\.claude-*//')

ACCOUNT_JSON="$CFG_DIR/.claude.json"
[ -f "$ACCOUNT_JSON" ] || ACCOUNT_JSON="$HOME/.claude.json"
ACCOUNT_EMAIL=$(jq -r '.oauthAccount.emailAddress // empty' "$ACCOUNT_JSON" 2>/dev/null)

USAGE_CACHE="$CFG_DIR/cache/oauth-usage.json"
USAGE_TTL=60  # seconds
mkdir -p "$CFG_DIR/cache" 2>/dev/null

now_epoch=$(date +%s)
cache_age=999999
[ -f "$USAGE_CACHE" ] && cache_age=$((now_epoch - $(stat -f %m "$USAGE_CACHE" 2>/dev/null || echo 0)))

# Fetch helper — saves response only if it's a successful body (has
# `.five_hour.utilization`). Rejects rate-limit / auth-error JSON so a
# transient failure doesn't poison the cache and erase line 3.
_fetch_usage() {
    local timeout=$1
    local token
    token=$(security find-generic-password -s "$KEYCHAIN_SVC" -w 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" 2>/dev/null)
    [ -z "$token" ] && return 1
    curl -s -m "$timeout" "https://api.anthropic.com/api/oauth/usage" \
        -H "Authorization: Bearer $token" \
        -o "$USAGE_CACHE.tmp" 2>/dev/null || { rm -f "$USAGE_CACHE.tmp"; return 1; }
    if jq -e '.five_hour.utilization | numbers' "$USAGE_CACHE.tmp" >/dev/null 2>&1; then
        mv "$USAGE_CACHE.tmp" "$USAGE_CACHE"
    else
        rm -f "$USAGE_CACHE.tmp"
        return 1
    fi
}

if [ "$cache_age" -gt "$USAGE_TTL" ]; then
    # Cold start (cache file missing) → sync fetch with short timeout so the
    # very first render after a Claude Code restart still shows line 3.
    # Subsequent stale refreshes stay async (line 3 keeps working from old
    # cache while fresh data lands in the background).
    if [ ! -f "$USAGE_CACHE" ]; then
        _fetch_usage 2
    else
        ( _fetch_usage 4 ) >/dev/null 2>&1 &
    fi
fi

# --- Format reset time as "Xm" / "Xh Ym" / "DAY HH:MM" ---
fmt_reset() {
    local iso=$1
    [ -z "$iso" ] || [ "$iso" = "null" ] && { echo ""; return; }
    local target_epoch
    target_epoch=$(python3 -c "import sys; from datetime import datetime; print(int(datetime.fromisoformat('$iso'.replace('Z','+00:00')).timestamp()))" 2>/dev/null)
    [ -z "$target_epoch" ] && { echo ""; return; }
    local delta=$((target_epoch - now_epoch))
    if [ "$delta" -lt 0 ]; then echo "now"
    elif [ "$delta" -lt 3600 ]; then echo "$((delta / 60))m"
    elif [ "$delta" -lt 86400 ]; then echo "$((delta / 3600))h $(((delta % 3600) / 60))m"
    else
        # Multi-day → just the day name in user's local TZ
        date -r "$target_epoch" +"%a %H:%M" 2>/dev/null
    fi
}

# --- Color a percentage by threshold (same scale as context bar) ---
pct_color() {
    local p=$1
    if [ "$p" -ge 90 ]; then printf '\e[31m'      # red
    elif [ "$p" -ge 75 ]; then printf '\e[33m'    # yellow
    elif [ "$p" -ge 60 ]; then printf '\e[37m'    # white
    else printf '\e[32m'; fi                       # green
}

# --- Build plan-usage line (only if cache file exists) ---
plan_line=""
if [ -f "$USAGE_CACHE" ]; then
    fh_pct=$(jq -r '.five_hour.utilization // empty | floor' "$USAGE_CACHE" 2>/dev/null)
    fh_reset=$(fmt_reset "$(jq -r '.five_hour.resets_at // empty' "$USAGE_CACHE" 2>/dev/null)")
    sd_pct=$(jq -r '.seven_day.utilization // empty | floor' "$USAGE_CACHE" 2>/dev/null)
    sd_reset=$(fmt_reset "$(jq -r '.seven_day.resets_at // empty' "$USAGE_CACHE" 2>/dev/null)")
    son_pct=$(jq -r '.seven_day_sonnet.utilization // empty | floor' "$USAGE_CACHE" 2>/dev/null)
    # Model-scoped weekly window (kind="weekly_scoped" in the `limits` array — the one
    # Fable burns; /usage labels it "Current week (Fable)"). Invisible in the two named
    # top-level fields, so it is read from the array (verified 7.9.2026 on the live cache).
    sc_pct=$(jq -r '[.limits[]? | select(.kind=="weekly_scoped")][0] | .percent // empty | floor' "$USAGE_CACHE" 2>/dev/null)
    sc_reset=$(fmt_reset "$(jq -r '[.limits[]? | select(.kind=="weekly_scoped")][0] | .resets_at // empty' "$USAGE_CACHE" 2>/dev/null)")
    sc_name=$(jq -r '[.limits[]? | select(.kind=="weekly_scoped")][0] | .scope.model.display_name // "scoped" | ascii_downcase' "$USAGE_CACHE" 2>/dev/null)

    parts=()
    if [ -n "$fh_pct" ]; then
        col=$(pct_color "$fh_pct")
        if [ -n "$fh_reset" ]; then
            parts+=("session ${col}${fh_pct}%${reset}${dim} (${fh_reset})${reset}")
        else
            parts+=("session ${col}${fh_pct}%${reset}")
        fi
    fi
    if [ -n "$sd_pct" ]; then
        col=$(pct_color "$sd_pct")
        if [ -n "$sd_reset" ]; then
            parts+=("week ${col}${sd_pct}%${reset}${dim} (${sd_reset})${reset}")
        else
            parts+=("week ${col}${sd_pct}%${reset}")
        fi
    fi
    if [ -n "$sc_pct" ]; then
        col=$(pct_color "$sc_pct")
        if [ -n "$sc_reset" ]; then
            parts+=("${sc_name} ${col}${sc_pct}%${reset}${dim} (${sc_reset})${reset}")
        else
            parts+=("${sc_name} ${col}${sc_pct}%${reset}")
        fi
    fi
    if [ -n "$son_pct" ]; then
        col=$(pct_color "$son_pct")
        parts+=("sonnet ${col}${son_pct}%${reset}")
    fi

    # Free disk space, in GB. The operator's request, 7.9.2026 — it belongs on the line that updates,
    # not only in the end-of-session summary, because the thing it warns about builds up
    # DURING a session: four agent worktrees once took this volume to 97 %.
    #
    # No cache, deliberately: `df -k` measured at ~2 ms per call (10 calls in 0.020 s
    # total, 7.9.2026), which is below the noise of everything else on this line. The
    # `oauth-usage.json` cache above exists because that one is a network round trip.
    #
    # GB, not GiB: `df -h` prints GiB and calling that GB is wrong by 7 % — the same
    # volume reads 60G under -h and 64.9 GB here. The arithmetic below converts from -k.
    disk_gb=$(df -k /System/Volumes/Data 2>/dev/null | awk 'NR==2 {printf "%.0f", $4*1024/1000000000}')
    if [ -n "$disk_gb" ]; then
        # Thresholds are about what this machine needs, not percentages: one agent
        # worktree's DerivedData is ~5 GB and an archive needs room on top of that.
        if [ "$disk_gb" -lt 15 ]; then
            dcol=$'\e[31m'        # red — an archive will not fit
        elif [ "$disk_gb" -lt 40 ]; then
            dcol=$'\e[33m'        # yellow — one more worktree's DerivedData and it is tight
        else
            dcol="$dim"
        fi
        parts+=("${dcol}disk ${disk_gb} GB${reset}")
    fi

    if [ ${#parts[@]} -gt 0 ]; then
        sep=" ${dim}·${reset} "
        plan_line="${parts[0]}"
        for ((i=1; i<${#parts[@]}; i++)); do
            plan_line="${plan_line}${sep}${parts[i]}"
        done
    fi
fi

# --- Output ---
printf '%s%s%s · %s\n' "$dim" "$project" "$reset" "$model"
printf '%s%s%s %d%% %s·%s %s/%s' "$bar_color" "$bar" "$reset" "$pct" "$dim" "$reset" "$used_fmt" "$total_fmt"

# Line 3 starts with WHO the session is logged in as. A non-default profile is
# printed in cyan (not dim) so a second subscription is visible at a glance.
acct=""
if [ -n "$ACCOUNT_EMAIL" ]; then
    if [ -n "$PROFILE_TAG" ]; then
        acct="${cyan}${PROFILE_TAG}:${ACCOUNT_EMAIL}${reset}"
    else
        acct="${dim}${ACCOUNT_EMAIL}${reset}"
    fi
elif [ -n "$PROFILE_TAG" ]; then
    acct="${cyan}${PROFILE_TAG}${reset}"
fi

if [ -n "$acct" ] && [ -n "$plan_line" ]; then
    printf '\n%s %s·%s %s' "$acct" "$dim" "$reset" "$plan_line"
elif [ -n "$plan_line" ]; then
    printf '\n%s' "$plan_line"
elif [ -n "$acct" ]; then
    printf '\n%s' "$acct"
fi
