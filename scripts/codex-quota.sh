#!/bin/bash
# Is there a reason NOT to send a review through the Codex CLI right now?
#
# ⚠️ The question this answers changed on 5.8.2026. It used to be "how much subscription quota is
# left", and it printed routing advice — "send the review over the API, not the Codex CLI" — that
# silently assumed Codex bills to the subscription. That day Codex was switched to `auth_mode:
# apikey`, and the advice became actively wrong: it pointed away from the CLI and towards the API
# for a model that was, at that moment, the SAME model on the SAME billing, minus repo access.
# I followed it and ran the tool-less variant of a review that the tool-armed one could have done.
#
# So the mode is read FIRST and the quota only matters when it is what pays.
#
# ⚠️ PROVENANCE: the quota figure is NOT a live query. Codex writes `rate_limits` into its session
# JSONL on `token_count` events, so this reports the value **as of the last codex run**, and only
# from runs where the server populated the window (many events carry nulls). The age is printed
# for exactly that reason — an old reading is a weak basis for a routing decision.
#
# Exit codes:
#   0 = nothing blocks the Codex CLI (plenty of quota, or billing is per-token)
#   1 = subscription quota is low (>=80 % used) AND the subscription is what pays
#   2 = mode is subscription but no quota reading could be found
#
# Usage: ~/.claude/scripts/codex-quota.sh

AUTH="$HOME/.codex/auth.json"
MODE="unknown"
if [ -f "$AUTH" ]; then
    MODE=$(python3 -c "
import json,sys
try: print(json.load(open('$AUTH')).get('auth_mode') or 'unknown')
except Exception: print('unknown')
")
fi

if [ "$MODE" != "chatgpt" ]; then
    echo "auth_mode: $MODE  (from ~/.codex/auth.json)"
    echo
    if [ "$MODE" = "unknown" ]; then
        # An unreadable mode is not "nothing blocks" — it is no reading (exit 2, like a missing
        # quota value). It used to fall through to exit 0 (review finding, 20.9.2026).
        echo "⚠️  Could not read the mode from ~/.codex/auth.json — no routing decision can rest on"
        echo "    this run. The subscription quota binds when the subscription pays; check the file."
        exit 2
    fi
    echo "✅ The subscription quota does not bind: Codex is billing per token, the same as a direct"
    echo "   API call. Route on COST and on capability, not on quota."
    echo
    echo "   The CLI is the tool-ARMED option — it reads the repo, so it can check target"
    echo "   membership, call sites and switch exhaustiveness that a diff-only reviewer states it"
    echo "   cannot. Measured 5.8.2026 on one review: tool-armed \$9.48 vs tool-less ~\$0.54 (17×),"
    echo "   and 96 % of the input was cached context re-sent by the agentic loop, which was 45 %"
    echo "   of the bill. You are paying for it to walk the repo, not to think."
    echo
    echo "   ⚠️ One 'codex exec' writes SEVERAL session logs (four, that day). Pricing the newest"
    echo "      one alone under-counted the run by 4×. Sum a whole day, and treat the billing"
    echo "      dashboard as the authority over the local logs — they disagreed by 12.6 %."
    exit 0
fi

python3 << 'PYEOF'
import json, glob, os, sys, datetime

files = sorted(glob.glob(os.path.expanduser('~/.codex/sessions/**/*.jsonl'), recursive=True),
               key=os.path.getmtime, reverse=True)

best = None
for f in files[:120]:
    for line in open(f, errors='ignore'):
        if '"rate_limits"' not in line:
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        rl = (d.get('payload') or {}).get('rate_limits') or {}
        win = rl.get('primary') or rl.get('secondary')
        if not win:
            continue
        ts = d.get('timestamp')
        if ts and (best is None or ts > best[0]):
            best = (ts, rl, win)
    if best:
        break

print("auth_mode: chatgpt  -> the subscription is what pays, so the window below binds.\n")

if not best:
    print("❌ No populated window in the recent session logs — the quota cannot be read locally.")
    print("   Run anything through 'codex exec' and retry, or decide without this figure.")
    sys.exit(2)

ts, rl, win = best
used = win.get('used_percent')
reset = win.get('resets_at')
age_h = (datetime.datetime.now(datetime.timezone.utc)
         - datetime.datetime.fromisoformat(ts.replace('Z', '+00:00'))).total_seconds() / 3600

print(f"plan:      {rl.get('plan_type') or '?'}  (limit_id={rl.get('limit_id')})")
print(f"used:     {used:>6.0f} %   window {win.get('window_minutes', 0) // 60} h")
if reset:
    d = datetime.datetime.fromtimestamp(reset)
    left = d - datetime.datetime.now()
    print(f"resets:    {d:%-d.%-m.%Y %H:%M}  (in {left.days} d {left.seconds // 3600} h)")
print(f"reading age: {age_h:.1f} h  <- from the last codex run, NOT a live value")

if used is not None and used >= 80:
    print(f"\n⚠️  LOW ({100 - used:.0f} % left) -> send the review over the API (gpt-5.6-sol), not the Codex CLI.")
    print("    ⚠️ That loses repo access: the API variant states what it could not verify")
    print("       (target membership, call sites, switch exhaustiveness) and you verify those by hand.")
    sys.exit(1)
print(f"\n✅ {100 - (used or 0):.0f} % left -> the review can go through the Codex CLI (subscription).")
PYEOF
