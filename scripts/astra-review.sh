#!/usr/bin/env bash
# astra-review.sh — gpt-6-astra as a tool-armed reviewer. THE PREMIUM LANE.
#
# 🔴 RUN THIS WHEN THE HUMAN OPERATOR HAS EXPLICITLY ASKED FOR ASTRA, AND NOT OTHERWISE. Not "this looks hard",
#    not "sol found nothing", not as a retry after a failed run. The gate below is a
#    sentence about THEM, so writing it without having been asked is a lie, not a slip.
#
# What it is: the same review pipeline as sol-review.sh — same shared guard, same
# modes, same truncation/quota checks — with the model swapped. There is deliberately
# NO second copy of that logic here: the guard file already went missing from
# agy-review.sh once (23.7.2026) because two wrappers looked finished side by side,
# and a duplicated 379-line script is that failure with a longer fuse.
#
# Measured 5.9.2026 on this machine (codex-cli 0.153.4):
#   - `gpt-6-astra` is in the account's /v1/models list AND answers through the Codex
#     CLI: the run header echoed `model: gpt-6-astra`, rc=0, 8,739 tokens for a
#     one-word probe. The header is the discriminator — a slug that answers is not
#     proof the slug is what served it.
#   - reasoning effort `high` AND `xhigh` both accepted and both completed (rc=0).
#     sol-review.sh defaults to `high`; here `xhigh` is the default, because the only
#     reason to reach for this lane is that the cheaper one was not enough.
#   - `~/.codex/config.toml` already sets `model = "gpt-6-astra"` globally, so an
#     UNQUALIFIED `codex exec` runs astra today. sol-review.sh is safe from that only
#     because it passes `-c model=...` explicitly. Do not remove that flag anywhere.
#
# Cost. This runs on the ChatGPT subscription, so what binds is the weekly Codex
# window (`~/.claude/scripts/codex-quota.sh`), not a dollar figure. For scale, the
# API list price is $10/$50 per 1M in/out — 2.5x gpt-5.6-sol (verified 5.9.2026 on
# developers.openai.com/api/docs/models/gpt-6-astra: 1,050,000 context, 128k max
# output, cutoff 30.4.2026).
#
# The completion sentinel stays `=== SOL REVIEW COMPLETE ===`. It is a token the
# wrapper greps for, not a label of who ran — renaming it here would silently break
# sol-review.sh's truncation check, and a truncated run would then read as a clean one.
#
# Usage:
#   astra-review.sh --human-asked {plan|review|verify} <repo> <brief> [out]
#   ASTRA_CONFIRM=human-asked astra-review.sh {plan|review|verify} <repo> <brief> [out]
#   (the pre-20.9.2026 spellings of the flag and the env value are refused since 20.9.2026 evening)
#
# Env: ASTRA_MODEL (default gpt-6-astra) · ASTRA_EFFORT (xhigh) · ASTRA_TIMEOUT (45m)
#      ASTRA_DETACH=1 -> same detached contract as SOL_DETACH (poll <out>.done)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOL="$HERE/sol-review.sh"

# The gate comes FIRST: before argument parsing, before any path check, before
# anything that could exit 0 on its own. A guard that can be reached only on the
# happy path is not a guard.
case "${1:-}" in
    --human-asked) ASTRA_CONFIRM=human-asked; shift ;;
esac

if [ "${ASTRA_CONFIRM:-}" != "human-asked" ]; then
    cat >&2 <<'GATE'
error: astra-review.sh is the PREMIUM lane and did not run.

  gpt-6-astra costs 2.5x sol per token and eats the shared weekly Codex window
  that every other review also draws from. It runs only when the human you work
  for has asked for astra in this conversation, in their own words.

  If they did:     astra-review.sh --human-asked <mode> <repo> <brief> [out]
  If they did not: use sol-review.sh. Do NOT "just try astra" after a weak sol run
  and do NOT pass this flag to get past this message — the phrase is a claim
  about them, and nothing here can check it except you.
GATE
    exit 2
fi

[ -x "$SOL" ] || { echo "error: sol-review.sh not found next to this script: $SOL" >&2; exit 1; }

# Delegate. Everything below the model choice — the shared guard file, the read-only
# sandbox, the timeout watchdog, the quota/truncation guards, the detach contract —
# lives in sol-review.sh and is deliberately not re-implemented.
export SOL_MODEL="${ASTRA_MODEL:-gpt-6-astra}"
export SOL_EFFORT="${ASTRA_EFFORT:-xhigh}"
export SOL_TIMEOUT="${ASTRA_TIMEOUT:-45m}"
[ "${ASTRA_DETACH:-}" = "1" ] && export SOL_DETACH=1

echo "🔶 astra-review: PREMIUM lane · model=$SOL_MODEL effort=$SOL_EFFORT timeout=$SOL_TIMEOUT" >&2
exec "$SOL" "$@"
