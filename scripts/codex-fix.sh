#!/usr/bin/env bash
# codex-fix.sh — the WRITE lane. Takes a list of findings and lets Codex fix them
# in an isolated git worktree, then hands back a diff nobody has merged yet.
#
# This is deliberately NOT a flag on sol-review.sh / astra-review.sh:
#
#   1. A reviewer that writes reviews its own patch on the next pass. Finder and
#      fixer have to be two runs, or the second layer is gone and the output looks
#      exactly the same.
#   2. sol-review.sh's prompt FORBIDS running tests, and that ban exists because its
#      sandbox is read-only (`mktemp` fails there; 29.7.2026 a run burned nine minutes
#      on a false "Layer A RED"). Flipping the sandbox would leave that sentence in the
#      prompt while it stopped being true.
#   3. Writing into the shared checkout collides with a parallel session (skill
#      `multi-session`). Hence the worktree below — it is not optional.
#
# Measured 5.9.2026 (codex-cli 0.153.4): `codex exec -s workspace-write` edits files
# with no approval prompt in non-interactive mode (test repo: a.txt went x=1 -> x=2,
# `git status` showed ` M a.txt`, the run printed the unified diff). Sandbox modes are
# read-only | workspace-write | danger-full-access; this script uses the middle one and
# never `--dangerously-bypass-*`.
#
# Usage:
#   codex-fix.sh [--human-asked] [--astra] <repo-dir> <findings-file> [out-file]
#   codex-fix.sh --cleanup <worktree-dir>          # after you merged or discarded it
#
# Env: FIX_MODEL (default gpt-5.6-sol) · FIX_EFFORT (high) · FIX_TIMEOUT (40m)
#      FIX_WORKTREE (override the worktree path) · FIX_NO_RUN=1 (prepare the tree and
#      stop, no model call) · FIX_NPM=0 (skip the dependency install)
#      FIX_NPM_DIRS="a b" (install only these, relative to the repo root)
#
# What the RUN never does: commit, push, merge, or delete the worktree. The diff is
# the product; a human decides what happens to it. Removal is the separate --cleanup
# subcommand, and it is not optional housekeeping — see there.

set -euo pipefail

HERE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── --cleanup <worktree>: teardown, and the only way this script removes anything ────
#
# Why it is a subcommand and not the tail of a run: at the end of a run nobody has read
# the diff yet, so removing the tree there would throw away work whose only copy it is.
# Cleanup happens after a human merged (or rejected) it — and it has to happen, because
# the two things it collects are the two that fill the disk:
#   * the worktree itself
#   * its DerivedData, which `git worktree remove` knows nothing about — ~5 GB per tree
#     that ever built (measured 30.8.2026: four agent worktrees held 19.6 GB while the
#     volume was at 97 %)
if [ "${1:-}" = "--cleanup" ]; then
    WT="${2:-}"
    [ -n "$WT" ] || { echo "usage: $(basename "$0") --cleanup <worktree-dir>" >&2; exit 2; }
    [ -d "$WT" ] || { echo "error: not a directory: $WT" >&2; exit 1; }
    WT="$(cd "$WT" && pwd)"

    # Refuse anything outside ~/.claude/worktrees/. The path is the evidence; a hash or a
    # date is not (multi-session skill §8 — a removed worktree leaves a FRESHLY dated
    # DerivedData dir, so mtime points at the wrong one).
    case "$WT" in
        "$HOME/.claude/worktrees/"*) ;;
        *) echo "error: REFUSING $WT — not under ~/.claude/worktrees/" >&2; exit 1 ;;
    esac

    MAIN="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's/\.git$//')"
    MAIN="${MAIN%/}"
    WT_BRANCH="$(git -C "$WT" rev-parse --abbrev-ref HEAD)"
    WT_HEAD="$(git -C "$WT" rev-parse HEAD)"

    # The five checks, in the order that makes a refusal informative. FIX_CLEANUP_FORCE=1
    # skips only the first three (uncommitted / stash / unmerged), never the path guard.
    DIRTY=$(git -C "$WT" status --porcelain --untracked-files=all | wc -l | tr -d ' ')
    STASHES=$(git -C "$WT" stash list | wc -l | tr -d ' ')
    # A repo with no origin/main (a scratch repo, a fork tracking another name) used to kill this
    # branch under `set -eo pipefail` with a bare rc=128 and no message (reproduced 20.9.2026 on a
    # scratch repo: `--cleanup` printed nothing and exited 128). Say "unknown" instead, which the
    # refusal below treats as not-proved-merged.
    if git -C "$WT" rev-parse --verify -q origin/main >/dev/null 2>&1; then
        UNMERGED=$(git -C "$WT" log --oneline origin/main.."$WT_BRANCH" 2>/dev/null | wc -l | tr -d ' ')
    else
        UNMERGED="unknown"
    fi

    if [ "${FIX_CLEANUP_FORCE:-}" != "1" ]; then
        REFUSE=""
        [ "$DIRTY" != "0" ]    && REFUSE="$REFUSE\n  - $DIRTY uncommitted/untracked file(s) — the fix diff may still be here, unread"
        [ "$STASHES" != "0" ]  && REFUSE="$REFUSE\n  - $STASHES stash entry/entries"
        [ "$UNMERGED" != "0" ] && REFUSE="$REFUSE\n  - $UNMERGED commit(s) on $WT_BRANCH not on origin/main (\"unknown\" = no origin/main to compare against)"
        if [ -n "$REFUSE" ]; then
            echo "error: REFUSING to remove $WT" >&2
            printf '%b\n' "$REFUSE" >&2
            echo "  Read the diff first. If it is genuinely disposable: FIX_CLEANUP_FORCE=1 $(basename "$0") --cleanup $WT" >&2
            exit 1
        fi
    fi

    echo "▶ cleanup: removing worktree $WT (branch $WT_BRANCH @ ${WT_HEAD:0:8})" >&2
    git -C "$MAIN" worktree remove --force "$WT"
    git -C "$MAIN" branch -D "$WT_BRANCH" >/dev/null 2>&1 || true
    git -C "$MAIN" worktree prune

    # 🔴 Verify the shared checkout did not follow us onto this branch — a pruned worktree
    # has moved it before (multi-session §8). Compare by name AND by SHA.
    MAIN_BRANCH="$(git -C "$MAIN" rev-parse --abbrev-ref HEAD)"
    echo "▶ cleanup: shared checkout $MAIN is on $MAIN_BRANCH @ $(git -C "$MAIN" rev-parse --short HEAD)" >&2
    [ "$MAIN_BRANCH" = "$WT_BRANCH" ] && echo "🔴 cleanup: the shared checkout is now on the REMOVED worktree's branch — fix that before anything else." >&2

    # DerivedData whose WorkspacePath pointed INTO the removed tree. Identify by that path,
    # never by size or date, and refuse anything not under ~/.claude/worktrees/.
    DD="$HOME/Library/Developer/Xcode/DerivedData"
    if [ -d "$DD" ]; then
        FREED=0
        for d in "$DD"/*-*; do
            [ -d "$d" ] || continue
            WP=$(/usr/libexec/PlistBuddy -c "Print :WorkspacePath" "$d/info.plist" 2>/dev/null) || continue
            case "$WP" in
                "$WT"/*|"$WT") ;;
                *) continue ;;
            esac
            case "$WP" in
                "$HOME/.claude/worktrees/"*) ;;
                *) echo "REFUSING $(basename "$d") — WorkspacePath is not a worktree: $WP" >&2; continue ;;
            esac
            SZ=$(du -sm "$d" 2>/dev/null | cut -f1)
            echo "▶ cleanup: DerivedData $(basename "$d") (${SZ} MB) -> $WP" >&2
            # A Debug product that was RUN leaves a root:wheel _MASReceipt, so rm half-succeeds
            # and a 52 KB shell survives — which still satisfies [ -e ] for every later sweep.
            rm -rf "$d" 2>/dev/null || true
            if [ -e "$d" ]; then
                ROOTFILES=$(find "$d" -user root 2>/dev/null | wc -l | tr -d ' ')
                echo "⚠️  cleanup: $(basename "$d") survived rm with $ROOTFILES root-owned file(s)." >&2
                echo "    Finish it by hand: sudo rm -rf '$d'" >&2
            else
                FREED=$((FREED + SZ))
            fi
        done
        echo "▶ cleanup: freed ${FREED} MB of DerivedData" >&2
    fi
    exit 0
fi

# ── --astra: the premium model, behind the SAME gate astra-review.sh uses ────────────
#
# `--human-asked` is the flag form of ASTRA_CONFIRM, mirroring the gate in astra-review.sh.
# It exists for a permission-layer reason, not a usability one: a `Bash()` rule matches a
# command PREFIX, and `ASTRA_CONFIRM=human-asked codex-fix.sh …` begins with the env
# assignment, so no rule naming this script can match it. Measured 7.9.2026 across the 44
# allow rules in settings.json — not one carries an ENV=value prefix, so there was no
# precedent to rely on either.
#
# 🔴 The flag is still a CLAIM about the human operator, not a switch: what moved is where
# it is spelled, not who may spell it. Both forms are accepted and behave identically (verified
# 7.9.2026 by running all four: `--astra` alone is refused by the gate below, the flag
# passes it, the reversed order behaves the same, and the env form passes). Renamed to
# `--human-asked` on 20.9.2026 for the public export; the 7.9. spelling was accepted as an
# alias for one day and is refused since (the operator's decision, 20.9.2026 evening).
#
# ⚠️ And with this script in `permissions.allow` (7.9.2026, the operator's decision) the prompt
# that used to enforce the gate is gone — a prompt raised in a subagent or in another
# session's terminal is not one they see, which is why `ask` was not the answer. Nothing
# now stops a run except this check. There is no run log and no budget; if the cost of
# that becomes visible, a per-week cap inside this script is the replacement that does
# not need them watching.
USE_ASTRA=0
while :; do
    case "${1:-}" in
        --human-asked) ASTRA_CONFIRM=human-asked; shift ;;
        --astra)        USE_ASTRA=1; shift ;;
        --*)            echo "error: unknown option $1 (the gate flag is --human-asked)" >&2; exit 2 ;;
        *)              break ;;
    esac
done
if [ "$USE_ASTRA" = "1" ] && [ "${ASTRA_CONFIRM:-}" != "human-asked" ]; then
    cat >&2 <<'GATE'
error: --astra is the PREMIUM model and did not run.

  gpt-6-astra costs 2.5x sol per token and eats the shared weekly Codex window.
  It runs only when the human you work for has asked for astra in this conversation,
  in their own words.

  If they did:     codex-fix.sh --human-asked --astra <repo> <findings> [out]
                   (the env form ASTRA_CONFIRM=human-asked is accepted too)
  If they did not: drop --astra. A weak sol run is not a reason to escalate.
GATE
    exit 2
fi

REPO="${1:-}"
FINDINGS="${2:-}"
OUT="${3:-}"

if [ "$USE_ASTRA" = "1" ]; then
    MODEL="${FIX_MODEL:-gpt-6-astra}"
    EFFORT="${FIX_EFFORT:-xhigh}"
    TIMEOUT="${FIX_TIMEOUT:-60m}"
else
    MODEL="${FIX_MODEL:-gpt-5.6-sol}"
    EFFORT="${FIX_EFFORT:-high}"
    TIMEOUT="${FIX_TIMEOUT:-40m}"
fi

usage() {
    echo "usage: $(basename "$0") [--human-asked] [--astra] <repo-dir> <findings-file> [out-file]" >&2
    echo "       $(basename "$0") --cleanup <worktree-dir>" >&2
    echo "  env: FIX_MODEL (default: $MODEL), FIX_EFFORT ($EFFORT), FIX_TIMEOUT ($TIMEOUT)," >&2
    echo "       FIX_NO_RUN=1, FIX_NPM=0, FIX_NPM_DIRS=\"dir dir\"" >&2
    exit 2
}

[ -n "$REPO" ] && [ -n "$FINDINGS" ] || usage
[ -d "$REPO" ] || { echo "error: repo dir not found: $REPO" >&2; exit 1; }
[ -f "$FINDINGS" ] || { echo "error: findings file not found: $FINDINGS" >&2; exit 1; }
[ -s "$FINDINGS" ] || { echo "error: findings file is empty: $FINDINGS" >&2; exit 1; }
command -v codex >/dev/null || { echo "error: codex not in PATH" >&2; exit 1; }
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "error: not a git repo: $REPO" >&2; exit 1; }

# Absolute OUT before any cd — a relative path would otherwise land inside the
# worktree and be swept away with it (sol-review.sh lost a 2.2 MB transcript this
# way on 26.7.2026; there the file merely landed in the wrong repo, here it would
# sit in a directory whose whole point is to be thrown away).
if [ -n "$OUT" ]; then
    case "$OUT" in /*) ;; *) OUT="$(pwd)/$OUT" ;; esac
fi

REPO="$(cd "$REPO" && pwd)"
REPO_NAME="$(basename "$REPO")"
BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"
BASE_REF="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"

# A dirty checkout is not an error — the worktree branches from HEAD, so uncommitted
# work simply is not part of what gets fixed. Saying so beats discovering it in the diff.
DIRTY=$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ')
if [ "$DIRTY" != "0" ]; then
    echo "⚠️  $REPO has $DIRTY uncommitted change(s). The fix runs against HEAD ($BASE_SHA)," >&2
    echo "    so those changes are NOT visible to it and cannot be fixed by this run." >&2
fi

TS="$(date +%Y%m%d-%H%M%S)"
WT="${FIX_WORKTREE:-$HOME/.claude/worktrees/fix-$REPO_NAME-$TS}"
BRANCH="fix/codex-$TS"

# Under ~/.claude/worktrees/ on purpose: the DerivedData sweep in skill `multi-session`
# refuses to delete anything whose WorkspacePath is not under that prefix.
mkdir -p "$(dirname "$WT")"
[ -e "$WT" ] && { echo "error: worktree path already exists: $WT" >&2; exit 1; }

if [ -z "${FIX_DRY_RUN:-}" ]; then
echo "▶ codex-fix: worktree $WT" >&2
echo "▶ codex-fix: branch  $BRANCH  (from $BASE_REF @ ${BASE_SHA:0:8})" >&2
git -C "$REPO" worktree add -q -b "$BRANCH" "$WT" HEAD
fi

# ── Dependencies: a fresh worktree is a checkout of TRACKED files only ───────────────
#
# Everything gitignored is absent, and in a repo with npm packages that means `node_modules`.
# Without it nothing that depends on them runs — `wrangler`, `npm test` and every script the fix would use
# to REPRODUCE a finding fail for a reason that has nothing to do with the code, and the
# failure is indistinguishable from a real one. A session lost three rounds to exactly
# this on 28.8.2026.
#
# `npm ci` rather than `npm install`: it installs from the lockfile and does not REWRITE
# it, so the fix diff cannot come back carrying lockfile churn nobody asked for. When it
# refuses (no lockfile, or lock out of sync with package.json) we fall back and then
# restore the lockfile ourselves, because at this point the tree is HEAD and any lockfile
# change is the installer's, not the fix's.
install_deps() {
    [ "${FIX_NPM:-1}" = "0" ] && { echo "▶ codex-fix: FIX_NPM=0 — skipping dependency install" >&2; return 0; }
    command -v npm >/dev/null || { echo "⚠️  codex-fix: npm not in PATH — skipping dependency install" >&2; return 0; }

    local dirs
    if [ -n "${FIX_NPM_DIRS:-}" ]; then
        dirs="$FIX_NPM_DIRS"
    else
        # Tracked package.json only: an rglob would pick up leftovers no build uses.
        dirs=$(git -C "$WT" ls-files '*package.json' 'package.json' | grep -v node_modules | sed 's#/*package\.json$##' | sed 's#^$#.#' | sort -u)
    fi
    [ -n "$dirs" ] || { echo "▶ codex-fix: no package.json in this repo — nothing to install" >&2; return 0; }

    local n=0 failed=0
    for d in $dirs; do
        [ -f "$WT/$d/package.json" ] || { echo "⚠️  codex-fix: no package.json in $d — skipped" >&2; continue; }
        n=$((n + 1))
        if [ -f "$WT/$d/package-lock.json" ] && npm ci --prefix "$WT/$d" --no-audit --no-fund >/dev/null 2>&1; then
            echo "   ✓ npm ci   $d" >&2
        elif npm install --prefix "$WT/$d" --no-audit --no-fund >/dev/null 2>&1; then
            echo "   ✓ npm i    $d  (ci refused or no lockfile)" >&2
        else
            echo "   ✗ FAILED   $d — reproduction steps that need this package will not run" >&2
            failed=$((failed + 1))
        fi
    done
    echo "▶ codex-fix: dependencies installed in $n package(s), $failed failed" >&2

    # npm may still have touched a lockfile on the fallback path. The tree is HEAD, so any
    # change here is the installer's and must not ride along in the fix diff.
    local touched
    touched=$(git -C "$WT" status --porcelain -- '*package-lock.json' 'package-lock.json' | wc -l | tr -d ' ')
    if [ "$touched" != "0" ]; then
        echo "⚠️  codex-fix: npm modified $touched lockfile(s) — restoring them to HEAD so the fix diff stays clean" >&2
        git -C "$WT" checkout -- '*package-lock.json' 2>/dev/null || true
        git -C "$WT" checkout -- 'package-lock.json' 2>/dev/null || true
    fi
}
[ -z "${FIX_DRY_RUN:-}" ] && install_deps

# FIX_NO_RUN=1 -> the tree is prepared (worktree + dependencies) and we stop here. Exists
# so the setup can be verified, and used by hand, without spending a model run.
if [ "${FIX_NO_RUN:-}" = "1" ]; then
    echo "▶ codex-fix: FIX_NO_RUN=1 — tree prepared, no model call" >&2
    echo "  worktree : $WT" >&2
    echo "  branch   : $BRANCH" >&2
    echo "  cleanup  : $(basename "${BASH_SOURCE[0]}") --cleanup $WT" >&2
    exit 0
fi

read -r -d '' RULES <<'EOF' || true
You are fixing a list of findings in a git worktree that exists only for this run.
The tree is yours to edit. Nothing you do here reaches the developer's checkout until
a human reads your diff and decides to take it.

HARD RULES
- Do NOT run `git commit`, `git push`, `git rebase`, `git checkout <branch>` or anything
  that rewrites history. Leave every change UNCOMMITTED in the working tree — the diff
  is the product of this run.
- Touch only files a finding actually names or that the fix demonstrably requires. An
  unrelated cleanup in the same diff makes the whole thing harder to accept, so it costs
  more than it gives.
- Do not edit tests so they pass. If a test contradicts a finding, say so and stop on
  that finding.

PER FINDING, IN THIS ORDER
1. REPRODUCE FIRST. Run the thing: a test, a script, a curl, a log line. Paste the
   observation. If you cannot reproduce it, do not pretend — write NOT REPRODUCED and
   label whatever you then change a HYPOTHESIS.
2. Describe the failure in ONE sentence. Then say whether your change cancels that whole
   sentence or only the instance in front of you. Fixing one instance is allowed; calling
   it a fix of the mechanism when it is not, is not.
3. OBSERVE IT GONE. Re-run the same command after the change and paste the result. "The
   build is green" is not that observation unless the failure was a build error.
4. Say what stayed open, and why.

EVIDENCE IN THE CODE YOU WRITE
- A comment may state what the code does. A comment that states WHY, or makes a universal
  or negative claim ("only", "never", "always", "cannot happen"), must carry its evidence
  inline — (verified: <command | file:line>) — or must not be written.
- Do not write a comment describing the behaviour your own change just invalidated.

IF NOTHING NEEDS FIXING
An empty diff is a valid outcome. Report which findings you judged already-correct and
what you read to decide that. Do not manufacture a change to look productive.

MANDATORY REPORT, at the end of your output:

| # | Finding | Reproduced? | What changed (file + symbol) | Verification observed | Left open |

Then the LAST LINE of your output must be EXACTLY:
=== CODEX FIX COMPLETE ===
The wrapper greps for it to tell a finished run from a truncated one. Without it the
output is treated as incomplete even if it looks finished.
EOF

PROMPT="$(printf '%s\n\n## FINDINGS TO FIX\n\n%s\n' "$RULES" "$(cat "$FINDINGS")")"

# FIX_DRY_RUN=1 -> print the composed prompt and exit, so the rules can be checked
# without spending a run. Same reason sol-review.sh has REVIEW_DRY_RUN: "the line is in
# the script" is not evidence that it reached the prompt.
if [ -n "${FIX_DRY_RUN:-}" ]; then
    printf '%s\n' "$PROMPT"
    # No worktree was created and no dependency was installed: a dry run is about the
    # PROMPT, and making it pay for six `npm ci` runs is how a check stops being run.
    echo "▶ codex-fix: DRY RUN — no worktree created, no model call" >&2
    exit 0
fi

case "$TIMEOUT" in
    *h) TIMEOUT_S=$(( ${TIMEOUT%h} * 3600 )) ;;
    *m) TIMEOUT_S=$(( ${TIMEOUT%m} * 60 )) ;;
    *s) TIMEOUT_S=${TIMEOUT%s} ;;
    *)  TIMEOUT_S=$TIMEOUT ;;
esac

echo "▶ codex-fix: model=$MODEL effort=$EFFORT timeout=$TIMEOUT sandbox=workspace-write" >&2

cd "$WT"
set +e
if [ -n "$OUT" ]; then
    codex exec -s workspace-write -c "model=\"$MODEL\"" -c "model_reasoning_effort=\"$EFFORT\"" \
        "$PROMPT" > >(tee "$OUT") 2>&1 &
    CODEX_PID=$!
    # Second-granularity watchdog, NOT `( sleep "$TIMEOUT_S"; kill … ) &`: killing that
    # subshell leaves its `sleep` orphaned (ppid=1) still holding the caller's stdout, so
    # a piped caller blocks for the whole timeout after the run has finished. Reproduced
    # in sol-review.sh on 5.9.2026 and fixed there the same way; this loop also exits on
    # its own as soon as codex is gone.
    ( left=$TIMEOUT_S
      while [ "$left" -gt 0 ]; do
          sleep 1
          kill -0 "$CODEX_PID" 2>/dev/null || exit 0
          left=$((left - 1))
      done
      kill "$CODEX_PID" 2>/dev/null && \
      echo "▶ codex-fix: TIMEOUT after ${TIMEOUT} — run cut short, the tree is HALF-FIXED" >&2 ) &
    WATCHDOG=$!
    wait "$CODEX_PID"
    RC=$?
    # Reap the watchdog quietly. A bare `kill` leaves the shell to announce
    # "Terminated: 15" on stderr when it reaps the job, which lands in the middle of
    # the report and reads like the RUN was killed (observed 5.9.2026 in a run that
    # finished normally, rc=0).
    { kill "$WATCHDOG" && wait "$WATCHDOG"; } 2>/dev/null || true
else
    codex exec -s workspace-write -c "model=\"$MODEL\"" -c "model_reasoning_effort=\"$EFFORT\"" "$PROMPT"
    RC=$?
fi
set -e

echo "▶ codex-fix rc=$RC" >&2

CHANGED=$(git -C "$WT" status --porcelain | wc -l | tr -d ' ')

if [ -n "$OUT" ]; then
    LINES=$(wc -l < "$OUT" | tr -d ' ')
    TAIL=$(tail -40 "$OUT")
    if [ "$LINES" -le 2 ] || printf '%s' "$TAIL" | grep -qiE 'usage limit reached|rate limit exceeded|quota exceeded|not authenticated|please run .?codex login'; then
        echo "error: the run produced no usable report (${LINES} lines)." >&2
        sed -n '1,3p' "$OUT" | sed 's/^/       | /' >&2
        echo "       Most common cause: the Codex weekly window is spent (this runs on the subscription)." >&2
        echo "       The worktree is LEFT IN PLACE with $CHANGED changed file(s): $WT" >&2
        exit 3
    fi
    if ! printf '%s' "$TAIL" | grep -qF '=== CODEX FIX COMPLETE ==='; then
        echo "error: run is TRUNCATED — ${LINES} lines of output, no closing sentinel." >&2
        echo "       🔴 The tree may be HALF-FIXED: $CHANGED changed file(s) in $WT" >&2
        echo "       Read the diff before you trust any of it; a partial fix looks like a whole one." >&2
        exit 4
    fi
fi

echo >&2
echo "── result ──────────────────────────────────────────────" >&2
git -C "$WT" --no-pager diff --stat >&2 || true
git -C "$WT" status --short >&2 || true
echo >&2
echo "  worktree : $WT" >&2
echo "  branch   : $BRANCH (from ${BASE_SHA:0:8})" >&2
echo "  diff     : git -C $WT diff" >&2
echo "  changed  : $CHANGED file(s), UNCOMMITTED — nothing was merged or pushed" >&2
echo "  cleanup  : $HERE_DIR/$(basename "${BASH_SOURCE[0]}") --cleanup $WT" >&2
echo "             ^ run it once the diff is merged or rejected — it takes the worktree AND" >&2
echo "               its DerivedData (~5 GB per tree that built), which nothing else collects" >&2
echo >&2
echo "🔴 The diff is a proposal, not a verified fix. The report's 'verification observed'" >&2
echo "   column is the model's account of its own run — re-run the reproduction yourself" >&2
echo "   before this reaches $BASE_REF." >&2
exit $RC
