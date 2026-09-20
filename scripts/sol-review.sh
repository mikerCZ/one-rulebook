#!/usr/bin/env bash
# sol-review.sh — gpt-5.6-sol via the Codex CLI as a tool-armed reviewer.
#
# Why via Codex and not via the API: sol is the strongest reviewer of MY OWN work
# (20.7.2026: it caught 4 of my 5 attempted fixes), but over `/v1/chat/completions`
# it sees only what I paste into the prompt — and then keeps answering "not visible in
# the provided code". That day it said so ~15×, and every such sentence I had to
# re-verify by hand. With repo access that class of answers disappears. On top of that,
# on 19.7. it was the one reviewer that found a pre-release blocker the others missed — and
# precisely with repo access via Codex.
#
# ⚠️ A NEW RISK that this switch ITSELF creates: via the API sol physically could not
# read my plan or my docs. With repo access it can — and `audit-briefing.md` #1 says
# that a reviewer who knows your reasoning does not verify it, it rationalises it.
# That is why the wrapper ALWAYS puts the ban on reading rationale documents into the
# prompt. Without it this tool is weaker than the API variant it replaces.
#
# Modes:
#   plan    — Phase 3, review of a design BEFORE implementation. The diff does not exist yet.
#   review  — Phase 5, review of finished code. Enforces the NET diff and per-claim evidence.
#   verify  — checking a list of factual claims against the code (a per-claim table).
#             Added 26.7.2026 for user documentation that is translated into many
#             languages, so an inaccuracy gets fixed once per language. Neither plan nor review
#             fitted that — plan expects a design, review expects a diff.
#
# Usage:
#   sol-review.sh plan   <repo> <brief-file> [out-file]
#   sol-review.sh review <repo> <brief-file> [out-file]
#   sol-review.sh verify <repo> <brief-file> [out-file]
#
# The sandbox is hard-wired read-only: the reviewer must not be able to write. Do not override.

set -euo pipefail

MODE="${1:-}"
REPO="${2:-}"
BRIEF="${3:-}"
OUT="${4:-}"

MODEL="${SOL_MODEL:-gpt-5.6-sol}"
EFFORT="${SOL_EFFORT:-high}"
TIMEOUT="${SOL_TIMEOUT:-25m}"

usage() {
    echo "usage: $(basename "$0") {plan|review|verify} <repo-dir> <brief-file> [out-file]" >&2
    echo "  env: SOL_MODEL (default: $MODEL), SOL_EFFORT ($EFFORT), SOL_TIMEOUT ($TIMEOUT)" >&2
    exit 2
}

[ -n "$MODE" ] && [ -n "$REPO" ] && [ -n "$BRIEF" ] || usage
[ -d "$REPO" ] || { echo "error: repo dir not found: $REPO" >&2; exit 1; }
[ -f "$BRIEF" ] || { echo "error: brief file not found: $BRIEF" >&2; exit 1; }
command -v codex >/dev/null || { echo "error: codex not in PATH" >&2; exit 1; }

case "$MODE" in
  plan|review|verify) ;;
  *) usage ;;
esac

# OUT to an absolute path BEFORE the `cd "$REPO"` below. A relative path would otherwise
# resolve against the repo, not against where I launched the script from — on 26.7.2026
# a 2.2 MB transcript landed that way as an untracked file in the project's source tree.
# Inconspicuous precisely because the script finishes successfully and the output exists; just elsewhere.
if [ -n "$OUT" ]; then
    case "$OUT" in
        /*) ;;
        *) OUT="$(pwd)/$OUT" ;;
    esac
fi

# Shared header — ONE source for both sol-review.sh and agy-review.sh (review-guard.md).
# Until 23.7.2026 these rules were written ONLY here and agy did not have them; nobody
# noticed, because both wrappers looked finished. A missing file is a HARD error:
# a guard that can be skipped silently is not a guard.
# Every line in there exists because of a concrete, paid-for mistake — see skills/audit-briefing/SKILL.md.
GUARD_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/review-guard.md"
[ -f "$GUARD_FILE" ] || {
    echo "error: shared guard not found: $GUARD_FILE" >&2
    echo "       Without it the reviewer would be allowed to read my conclusions (AUDIT_BACKLOG/KNOWN_BUGS/…)." >&2
    echo "       NOT STARTING — a run without the guard is worse than no run." >&2
    exit 1
}
# The leading HTML comment is a note for me, not for the model — it does not belong in the prompt.
SHARED_GUARD="$(sed '/^<!--/,/^-->$/d' "$GUARD_FILE")"
[ -n "${SHARED_GUARD//[[:space:]]/}" ] || {
    echo "error: $GUARD_FILE is empty once the comment is stripped — the guard would be a no-op." >&2
    exit 1
}

# Tool-specific remainder: this holds for sol (repo access, diff review),
# not necessarily for other reviewers — which is why it does NOT belong in the shared file.
read -r -d '' SOL_EXTRA <<'EOF' || true

📌 Cite SYMBOLS (function and property names), not line numbers — those rot.
   Every claim must point to a file you have OPENED.

🔍 Before you report a finding, try to REFUTE it. Write what you tried and why it survived.

⏱️ For every NEW call in `body`, in a computed property or in a loop, ask:
   what does it cost, how many times per second is it called, and what does it invalidate?

📉 DO NOT DUMP WHOLE FILES INTO THE REPLY. Read selectively — grep, specific line ranges,
   individual functions. Never more than ~80 lines from one file at a time. The reason is
   measured, not aesthetic: on 28.7.2026 a run of this review was killed after 3 m 50 s because
   it was pouring out 82 kB/min of transcript (it was pulling whole Swift files into it that had
   nothing to do with the assignment). The narrowed run went at 10 kB/min and finished fine —
   and yet the successful runs had 3× MORE output IN TOTAL than the killed one. Volume does not
   decide, pace does.

🧪 DO NOT RUN whole test suites (`test/run-all.sh`, `swift test`, `pytest`). The sandbox is
   read-only and `mktemp` fails in it, so the suite goes red BECAUSE OF THE ENVIRONMENT, not because
   of the code — and you then debug the environment instead of reviewing. Measured 29.7.2026: a run
   burnt nine minutes that way, arrived at a false „Layer A RED", announced it would try to run it
   outside the write ban, and was killed before it wrote a single finding. A single test
   (`node test/neco.test.mjs`) passes and you may run it. DO NOT WORK AROUND the sandbox — it is there on purpose.

🏁 The LAST LINE of the reply must be EXACTLY:
   === SOL REVIEW COMPLETE ===
   The wrapper uses it to recognise a truncated run. Without it the output is treated as
   incomplete — even if it looks finished.
EOF

GUARD="${SHARED_GUARD}
${SOL_EXTRA}"

if [ "$MODE" = "verify" ]; then
    read -r -d '' MODEPROMPT <<'EOF' || true
## ROLE: verifying CLAIMS against the code

You get a list of factual claims about this codebase. They are not proposals and not a diff —
they are sentences somebody wrote and wants to know whether they hold. Typically they are
headed for user documentation, so an inaccuracy then gets translated into further languages
and is expensive to fix.

MANDATORY FORMAT. A bare verdict is an INVALID reply and will be discarded.

| # | Claim | Symbol I opened (file + function/type) | What the code does | VERDICT |

VERDICT: MATCH / MISMATCH / PARTIAL / UNVERIFIABLE (say why it cannot be verified).

For every MISMATCH and PARTIAL, below the table:
  CLAIM SAYS / CODE DOES (file + symbol) / REFUTATION ATTEMPT (what you tried
  to make the finding go away, and why it survived) / IMPACT ON THE READER of the documentation.

Judge especially hard the claims about:
- privacy and where data goes (where exactly the request is sent, whose key is used),
- billing, limits and what is free,
- availability on platforms („evidence for a claim that something is NOT SOMEWHERE is harder
  to find than for the opposite — when you do not have it, it is UNVERIFIABLE, not MATCH").

Rules:
- Verify against the CODE, not against comments. A comment is somebody's unverified claim;
  when a comment and the code contradict each other, the code wins and you report the mismatch.
- Verify verbatim user-facing messages against `Localizable.xcstrings`, not against
  a paraphrase in the source.
- Do not invent mismatches to make the output look productive. An all-MATCH table is
  a valid reply — the table itself is the evidence that you went through it.
- Do not deal with style, wording or code quality. Only claim-says-X / code-does-Y.
EOF
elif [ "$MODE" = "plan" ]; then
    read -r -d '' MODEPROMPT <<'EOF' || true
## ROLE: review of a DESIGN before implementation (Phase 3)

The code for this design does NOT EXIST yet. So do not look for bugs in a diff — look for
why the design will not work once it is written. Specifically:

1. Architecture — is the approach right? Is there a simpler one that does the same?
2. Race conditions — await suspension points, @MainActor ordering, cancel
   propagation, reentrance across `await`.
3. WHAT THE DESIGN IS MISSING — files, call sites and platforms it should cover
   and does not. This is the most valuable thing you can do in this phase: **walk the repo
   and find the callers the design says nothing about.**
4. Backward compatibility — migrations, versioning, old clients.
5. Invariants the design DESCRIBES but nothing enforces. Say it out loud:
   a comment is not a guard.
EOF
else
    read -r -d '' MODEPROMPT <<'EOF' || true
## ROLE: review of FINISHED code (Phase 5)

The scope is the NET diff at HEAD, not the individual commits inside the range — they
revise each other, and judging them one by one produces false findings. Start with:

    git diff --stat <BASELINE> HEAD
    git diff <BASELINE> HEAD

Judge the RESULTING state; read files at HEAD.

Focus on:
1. Bugs — off-by-one, nil handling, race conditions, memory leaks, retain cycles.
2. Guards that have the right POSITION but no EFFECT. For each one ask:
   "if it looked the same but I gutted its effect, would anything notice?"
3. Moved code — did it leave an orphan behind? A comment describing behaviour that
   now lives elsewhere? A variable that is no longer used? Did it cross an `#if` boundary?
4. Security — data exposure, injection, auth bypass, PII in analytics.
5. Edge cases — timeout, nil, offline, cancel midway.
6. Distinguish PRE-EXISTING from INTRODUCED BY THIS DIFF via `git show <BASELINE>:<file>`.
   A pre-existing problem reported as today's regression is a false positive.
EOF
fi

PROMPT="$(printf '%s\n\n%s\n\n%s\n' "$GUARD" "$MODEPROMPT" "$(cat "$BRIEF")")"

# REVIEW_DRY_RUN=1 → print the assembled prompt and stop. It exists so that it can be
# VERIFIED that the guard really is in the prompt, without spending a whole run. The claim
# "the line is in the script" does not prove it made it into the prompt.
if [ -n "${REVIEW_DRY_RUN:-}" ]; then
    printf '%s\n' "$PROMPT"
    exit 0
fi

# ── SOL_DETACH=1: run in our OWN SESSION, out of reach of the caller's supervisor ──────────
#
# Why this exists. 4.9.2026 a review died at 13 minutes with 363 kB written and no sentinel,
# and the wrapper correctly reported a truncated run — but the run itself was fine. It was
# launched as a Claude Code background task, and that harness KILLS ITS BACKGROUND TASKS under
# memory pressure; two helper tasks in the same session got the explicit "stopped because the
# system is running low on memory" notice within the same minute. A 25-minute review sitting in
# a pool that is culled on pressure will keep dying, and each death costs the weekly Codex
# window (measured that day: the killed run cost 8 points, a completed one 3).
#
# ⚠️ The obvious suspect was WRONG, so do not re-fix it. This script already blames output rate
# (see the 28.7.2026 note in the guard), but the three runs that day measured 28.1 kB/min
# (KILLED), 47.8 kB/min (survived) and 37.0 kB/min (survived) — the dead one was the SLOWEST.
# Rate did not discriminate; the kill came from outside.
#
# `setsid(1)` does not exist on macOS, so the session is taken in Python: fork, the parent
# exits, the child calls setsid() and is then in a session of its own — a process-group kill
# aimed at the caller cannot reach it, and it has no controlling terminal to be hung up on.
#
# Contract for the caller, because detaching means nobody will notify you:
#   $OUT.pid   the detached PID, written before the child starts work
#   $OUT.log   everything the run printed (the wrapper's own stderr included)
#   $OUT.done  appears when the run has finished, and holds its exit code (verified 4.9.2026
#              by running it: written after subprocess.call returns, absent while the stub slept)
# Poll for $OUT.done rather than for $OUT, which keeps growing while the run is alive.
# 🔴 A missing $OUT.done reads as "still running", not as "clean" — a file that fails to appear
# has the same shape as a run nobody started.
if [ "${SOL_DETACH:-}" = "1" ] && [ "${SOL_DETACHED:-}" != "1" ]; then
    [ -n "$OUT" ] || { echo "error: SOL_DETACH=1 requires an out-file (4th argument) — without it there is nowhere to write the result." >&2; exit 2; }
    SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    rm -f "$OUT.done" "$OUT.pid"
    /usr/bin/python3 - "$SELF" "$MODE" "$REPO" "$BRIEF" "$OUT" <<'DETACH_PY'
import os, subprocess, sys
self_, mode, repo, brief, out = sys.argv[1:6]
if os.fork() > 0:
    os._exit(0)                      # parent returns to the shell at once
os.setsid()                          # a session of our own; the caller's group kill misses us
# Drop every inherited descriptor BEFORE any work. Measured 4.9.2026: without this the caller's
# `... | tail` blocks for the WHOLE run, because the pipe stays open while this process holds it —
# the launcher looks detached and the shell waits anyway, which is the bug this mode exists to fix.
_null = os.open(os.devnull, os.O_RDWR)
for _fd in (0, 1, 2):
    os.dup2(_null, _fd)
if _null > 2:
    os.close(_null)
with open(out + ".pid", "w") as fh:
    fh.write("%d\n" % os.getpid())
env = dict(os.environ, SOL_DETACHED="1")
with open(out + ".log", "wb") as fh:
    rc = subprocess.call([self_, mode, repo, brief, out],
                         stdin=subprocess.DEVNULL, stdout=fh, stderr=subprocess.STDOUT, env=env)
with open(out + ".done", "w") as fh:  # written LAST — its existence is the completion signal
    fh.write("%d\n" % rc)
DETACH_PY
    # The PID file is written by the grandchild, so it may not exist for a few ms.
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$OUT.pid" ] && break; sleep 0.2; done
    if [ ! -s "$OUT.pid" ]; then
        echo "error: detached start produced no PID file — the run did NOT start." >&2
        echo "       Do not read $OUT; it is stale or absent. See $OUT.log." >&2
        exit 5
    fi
    DPID=$(cat "$OUT.pid")
    # Verify the launch three ways rather than trusting that a command was issued: the PID file
    # exists, the process is alive, and it is in a DIFFERENT session than this shell.
    if ! kill -0 "$DPID" 2>/dev/null; then
        echo "error: detached PID $DPID is not alive — the run died at once. See $OUT.log." >&2
        exit 5
    fi
    # ⚠️ NOT `ps -o sess=` — on macOS that prints 0 for everything, so it cannot tell the two apart
    # (measured 4.9.2026: caller and detached child both read 0, and the check passed vacuously).
    # `setsid()` makes the child a session AND group leader, so its PGID equals its own PID; the
    # caller's does not. That difference is observable, which is the whole requirement here.
    MYPGID=$(ps -o pgid= -p $$ | tr -d ' ')
    DPGID=$(ps -o pgid= -p "$DPID" | tr -d ' ')
    if [ "$DPGID" != "$DPID" ] || [ "$DPGID" = "$MYPGID" ]; then
        echo "error: detached run is NOT in its own process group (pid=$DPID pgid=$DPGID, caller pgid=$MYPGID)." >&2
        echo "       A group kill aimed at the caller would take it down, so this mode bought nothing." >&2
        kill "$DPID" 2>/dev/null
        exit 5
    fi
    echo "▶ sol-review: DETACHED pid=$DPID pgid=$DPGID (caller pgid=$MYPGID)" >&2
    echo "▶ sol-review: poll for $OUT.done — it holds the exit code and is written at the end" >&2
    exit 0
fi

echo "▶ sol-review [$MODE] model=$MODEL effort=$EFFORT repo=$REPO" >&2

cd "$REPO"

# SOL_TIMEOUT was a DEAD VARIABLE until 27.7.2026: it was set, it was printed in the usage
# text as a supported option — and it was never passed to `codex exec`. So a run had no
# ceiling at all; a batch of 22 claims ran ~45 minutes before something outside killed it, and
# the whole output was lost. A configuration option that does nothing is worse than none: people
# plan by it.
#
# macOS has no GNU `timeout`, hence a watchdog in the background.
case "$TIMEOUT" in
    *h) TIMEOUT_S=$(( ${TIMEOUT%h} * 3600 )) ;;
    *m) TIMEOUT_S=$(( ${TIMEOUT%m} * 60 )) ;;
    *s) TIMEOUT_S=${TIMEOUT%s} ;;
    *)  TIMEOUT_S=$TIMEOUT ;;
esac

set +e
if [ -n "$OUT" ]; then
    # ⚠️ NOT `codex … | tee "$OUT" &` — in a pipeline `$!` is the PID of the LAST stage, i.e.
    # `tee`. The watchdog below would then kill `tee` and `codex` would go on running as an orphan.
    #
    # On 27.7.2026 it really ended that way and the mutation test DID NOT CATCH it, because it
    # passed for the wrong reason: the stub wrote to stdout continuously, so after `tee` was killed
    # it got SIGPIPE and died — it looked like a working timeout. The real `codex` flushes only
    # at the end, never hits SIGPIPE and survives. The control stub therefore MUST stay silent and
    # write only at the end, otherwise it tests a different property than the one that matters.
    #
    # Process substitution keeps `$!` on `codex`.
    codex exec -s read-only -c "model=\"$MODEL\"" -c "model_reasoning_effort=\"$EFFORT\"" \
        "$PROMPT" > >(tee "$OUT") 2>&1 &
    CODEX_PID=$!
    # ⚠️ NOT `( sleep "$TIMEOUT_S"; kill … ) &`. The `kill "$WATCHDOG"` below kills the subshell,
    # but NOT its child `sleep` — that one is orphaned (ppid=1) and keeps HOLDING the inherited stdout.
    # A caller that pipes the output (`| tee`, `| grep`, `$(...)`) then waits the whole
    # TIMEOUT, even though the review finished in a second. And because the $OUT file is complete
    # and correct, it looks like a slow model, not like a wrapper bug.
    # Reproduced 5.9.2026 with a stub `codex`: the run finished within 1 s, the caller hung 120 s
    # until the tool's timeout, `ps -A` showed `sleep 2700` with ppid=1 — after killing it the
    # command returned at once. The one-second loop holds the fd for at most 1 s and moreover
    # exits by itself as soon as codex is gone, so it does not wait out the rest of the window either.
    ( left=$TIMEOUT_S
      while [ "$left" -gt 0 ]; do
          sleep 1
          kill -0 "$CODEX_PID" 2>/dev/null || exit 0
          left=$((left - 1))
      done
      kill "$CODEX_PID" 2>/dev/null && \
      echo "▶ sol-review: TIMEOUT after ${TIMEOUT} — run killed, output is incomplete" >&2 ) &
    WATCHDOG=$!
    wait "$CODEX_PID"
    RC=$?
    # Reap the watchdog quietly. A bare `kill` leaves the shell to announce
    # "Terminated: 15" on stderr when it reaps the job, which lands in the middle of
    # the report and reads like the RUN was killed (observed 5.9.2026 in a run that
    # finished normally, rc=0).
    { kill "$WATCHDOG" && wait "$WATCHDOG"; } 2>/dev/null || true
else
    codex exec -s read-only -c "model=\"$MODEL\"" -c "model_reasoning_effort=\"$EFFORT\"" "$PROMPT"
    RC=$?
fi
set -e

echo "▶ sol-review rc=$RC" >&2

# An empty run must fail loudly — same reason as in agy-review.sh: exit 0
# on empty output is read by the caller as "it ran". `agy` has had a guard for it since
# 26.7.2026; sol did not have one until then, because its typical failure is different
# (exhausted quota / rate limit, not auto-deny). Verified by mutation with a stub `codex`.
if [ -n "$OUT" ]; then
    # The `tee` behind the process substitution is not waited for by `wait "$CODEX_PID"`; read the
    # file once its size has stopped moving, or a still-flushing tail reads as TRUNCATED (GLM
    # review finding, 20.9.2026 — not observed, prevented).
    prev=-1; for _ in 1 2 3 4 5 6 7 8 9 10; do sz=$(wc -c < "$OUT" | tr -d ' '); [ "$sz" = "$prev" ] && break; prev=$sz; sleep 0.3; done
    LINES=$(wc -l < "$OUT" | tr -d ' ')
    # Look for the sentinels ONLY in the tail of the output, not in the whole transcript.
    #
    # On 27.7.2026 this guard falsely failed a successful run (21 claims, full table)
    # on the line `// Rate limit: wait for per-provider interval` — i.e. on a COMMENT
    # in the source that the reviewer had read and printed into the transcript. A falsely
    # red guard with a convincing message is worse than a falsely green one: next time
    # somebody switches it off. The quota message always comes at the end, because the run ends with it.
    TAIL=$(tail -40 "$OUT")
    if [ "$LINES" -le 2 ] || printf '%s' "$TAIL" | grep -qiE 'usage limit reached|rate limit exceeded|quota exceeded|not authenticated|please run .?codex login'; then
        echo "error: the run produced no usable report (${LINES} lines)." >&2
        sed -n '1,3p' "$OUT" | sed 's/^/       | /' >&2
        echo "       Most common cause with sol: exhausted Codex quota (it runs on the subscription)." >&2
        echo "       The fallback is gpt-5.6-sol via the API (skill llm-apis) — see skills/llm-review/SKILL.md." >&2
        exit 3
    fi
    # THE ORDER IS LOAD-BEARING: only AFTER the quota guard. The other way round (as I wrote it
    # the first time) an exhausted account got the "narrow the brief" message, which does nothing
    # about quota — verified by mutation, cases D and E lit up red.
    # A truncated run: lots of text, no verdict. The empty-run guard above (that day it sat below) let it through as a
    # success — on 28.7.2026 it returned 315 kB without a single conclusion and the exit was taken as OK.
    # Same class as the empty run in agy-review.sh, only harder to spot: the file is
    # big, so `LINES -le 2` does not trip. Hence the sentinel the prompt insists on.
    if ! printf '%s' "$TAIL" | grep -qF '=== SOL REVIEW COMPLETE ==='; then
        echo "error: the run is TRUNCATED — ${LINES} lines of output, but the closing sentinel is missing." >&2
        echo "       The output in $OUT is partial and usable only up to where it ends." >&2
        echo "       Most common cause: output too fast (reading whole files)." >&2
        echo "       Narrow the brief to specific files and greps, then run again." >&2
        exit 4
    fi
fi
exit $RC
