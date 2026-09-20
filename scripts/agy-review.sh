#!/usr/bin/env bash
# agy-review.sh — Antigravity CLI (Gemini) as a tool-armed reviewer.
#
# Why a wrapper: agy has three traps that are easy to forget, and each one silently
# devalues the whole run (verified 20.7.2026, see skills/llm-review/SKILL.md):
#   1. It IGNORES `cd`. Without --add-dir it audits an empty scratch directory
#      (~/.gemini/antigravity-cli/scratch) and answers confidently about nothing.
#   2. Without an enforced evidence format it throws 100+ steps of real work away
#      into a single sentence ("the docs perfectly match the code").
#   3. It GUESSES line numbers (drift 20-30). Symbols it cites correctly.
#
# Modes:
#   survey  — first pass over the code. Inventory, map, call sites. The output is
#             RAW MATERIAL for the next step, not a conclusion. Errors here are caught downstream.
#   verify  — checking claims against the code. Enforces a per-claim table,
#             because a bare verdict from the verifier no longer runs into any check further on.
#
# Usage:
#   agy-review.sh survey <repo> <brief-file> [out-file]
#   agy-review.sh verify <repo> <brief-file> [out-file]
#
# Prerequisite: allow-rules for the read tools in ~/.gemini/antigravity-cli/settings.json (the
# live list has grown past read-only — measured 20.9.2026: 55 rules including cp, swift, node;
# `--mode plan` is what keeps a survey from writing, not the list)
# (rg, grep, ls, cat, head, tail, wc, file, git log/diff/show/ls-files/blame/
# rev-parse/merge-base) — otherwise headless mode auto-denies the tool calls.

set -euo pipefail

MODE="${1:-}"
REPO="${2:-}"
BRIEF="${3:-}"
OUT="${4:-}"

# Canonical model id, not the display name — `agy models` prints both columns and
# --model takes the id (verified 4.9.2026: `agy models` listed gemini-3.8-flash-high;
# 3.8 exists as Flash only, there is no gemini-3.8-pro row).
MODEL="${AGY_MODEL:-gemini-3.8-flash-high}"
TIMEOUT="${AGY_TIMEOUT:-25m}"
# Reasoning effort. Model IDs like `gemini-3.6-flash-high` already carry a tier,
# but `--effort` is a separate knob and the two are not the same thing — set both.
EFFORT="${AGY_EFFORT:-}"

usage() {
    echo "usage: $(basename "$0") {survey|verify} <repo-dir> <brief-file> [out-file]" >&2
    echo "  env: AGY_MODEL (default: $MODEL), AGY_TIMEOUT ($TIMEOUT), AGY_EFFORT (low|medium|high)" >&2
    exit 2
}

[ -n "$MODE" ] && [ -n "$REPO" ] && [ -n "$BRIEF" ] || usage
[ -d "$REPO" ] || { echo "error: repo dir not found: $REPO" >&2; exit 1; }
[ -f "$BRIEF" ] || { echo "error: brief file not found: $BRIEF" >&2; exit 1; }
command -v agy >/dev/null || { echo "error: agy not in PATH" >&2; exit 1; }

REPO_ABS="$(cd "$REPO" && pwd)"
HEAD_SHA="$(git -C "$REPO_ABS" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

# Shared header — ONE source for both sol-review.sh and agy-review.sh (review-guard.md).
# Until 23.7.2026 only sol had the ban on reading rationale documents; agy did not, and
# nobody noticed. A missing file is a HARD error: a guard that can be skipped silently
# is not a guard — without it the reviewer would be allowed to read docs/AUDIT_BACKLOG.md with my conclusions.
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

# The allowed commands are READ from the agy settings.json, not copied out — a copied list
# drifts and the model gets false information about what it may do.
#
# Why it is in the prompt at all: a SINGLE command outside the allow-list, at any point of the
# run, ends the whole run WITHOUT A REPLY. 26.7.2026 twice in a row, each time differently —
# first `cat <<'EOF' > /tmp/inventory.md` (a write), then `echo` (missing from the list).
# The second time 104 steps and 78 opened files were thrown away. The model does not know
# about the restriction until we tell it; tightening the wording about writing did not help,
# because writing is not the problem.
AGY_SETTINGS="${HOME}/.gemini/antigravity-cli/settings.json"
ALLOWED_CMDS="$(python3 - "$AGY_SETTINGS" <<'PY' 2>/dev/null || true
import json, re, sys
try:
    allow = json.load(open(sys.argv[1])).get("permissions", {}).get("allow", [])
except Exception:
    sys.exit(0)
names = []
for rule in allow:
    m = re.fullmatch(r"command\((.+)\)", rule.strip())
    if not m:
        continue
    body = m.group(1).strip()
    toks = body.split()
    # ONLY bare names and two-word prefixes such as "git log".
    #
    # Taking the first token of an arbitrary rule would LIE: settings.json has
    # `command(python3 scripts/check-translations.py)` and `command(curl -ILs … <jedna URL>)`,
    # from which "python3" and "curl" would fall out as if they were free. The model would use
    # them, get a deny and lose the whole run — i.e. exactly what this list is meant to prevent.
    if len(toks) > 2:
        continue
    if not all(re.fullmatch(r"[a-z0-9_.-]+", t) for t in toks):
        continue
    if body not in names:
        names.append(body)
print(", ".join(sorted(names)))
PY
)"

read -r -d '' SHELL_RULE <<EOF || true
## Shell — read this before you run anything

You are running headless. There is no one to approve a permission prompt, so a
command that is not pre-approved is auto-denied, and **a single denied command ends
the whole run with no reply at all** — every file you read up to that point is lost.

$([ -n "$ALLOWED_CMDS" ] && echo "The ONLY commands available to you are: ${ALLOWED_CMDS}." || echo "Only a small set of read-only commands is available.")
Anything else — including \`echo\`, \`printf\`, \`xargs\`, \`bash -c\`, or any redirection
that creates a file (\`>\`, \`>>\`, \`tee\`, heredoc into a path) — is denied and fatal.

Prefer the file-reading tool over shell entirely. Compose the report **in your reply**;
never build it up in a file.
EOF

# Common preamble — applies to both modes.
read -r -d '' PREAMBLE <<EOF || true
Repo: ${REPO_ABS} (HEAD ${HEAD_SHA}). Read-only task — do not edit, stage or commit anything.

${SHARED_GUARD}

${SHELL_RULE}

Cite SYMBOLS, never line numbers: "in \`loadPurchases\`, the early-return branch",
not ":1010". Line numbers rot and yours drift by 20-30 anyway. Give file path + symbol.
You must actually open every symbol you list; listing a file you did not read is a failure.
EOF

case "$MODE" in
survey)
    read -r -d '' MODE_RULES <<'EOF' || true

## Mode: SURVEY — first pass over the code

You are producing RAW MATERIAL for someone who will write documentation from it.
You are NOT producing conclusions. Your output gets checked downstream, so
completeness beats confidence.

- Map what actually exists: types, functions, call sites, order of operations,
  gates, defaults, fallbacks, per-platform differences, failure behaviour.
- Where two code paths do the same thing differently, say so — that asymmetry
  is the most valuable thing you can surface.
- Do NOT summarise into a verdict. A verdict here is worthless; the inventory is
  the deliverable.

## MANDATORY COVERAGE — your known failure mode is COMPRESSION, not error

Measured behaviour: you read broadly and then report one narrow slice. In a prior
run you opened 14 files across routing, per-platform and websocket code, and wrote
up exactly one of them — accurately, but the rest was silently discarded. A tidy
essay about the most interesting thing you found is a FAILED response here.

Therefore:

1. **Answer every numbered item in the task below, in order, under its own heading.**
   Reproduce the item's heading verbatim so coverage is checkable.
2. **An item you cannot fill gets the heading anyway**, followed by one of:
   - `NOTHING FOUND — searched: <what you grepped>` (you looked, there is nothing), or
   - `UNREAD — <file/area>` (you did not open it).
   Silence on an item is indistinguishable from having skipped it, and will be read
   as skipped.
3. **End with a coverage ledger**: every file you opened, one per line, with the
   item numbers it fed. A file you opened that fed nothing gets `— nothing used`,
   which is itself a useful signal.
4. Length is not a virtue, but neither is compression: if you opened 14 files and
   your output cites 3, you have thrown away the run.
5. **Print the full report as your reply.** Do NOT write it to a file and reply with
   a path — the caller captures stdout and a file reference reads as a failed run.
6. **You have NO write permission and no shell that can create files.** `>`, `>>`,
   `tee`, `cat <<EOF > path`, `mkdir`, `touch` and every other write will be DENIED,
   and a denied tool call ends the run with no reply at all. Measured 26.7.2026: a
   survey that had already opened 81 files across 106 steps was destroyed at the last
   step by `cat <<'EOF' > /tmp/inventory.md`. Everything you learned is lost that way.
   Compose the report in your reply directly.
EOF
    ;;
verify)
    read -r -d '' MODE_RULES <<'EOF' || true

## Mode: VERIFY — check claims against the code

MANDATORY OUTPUT FORMAT. A bare verdict is an INVALID response and will be discarded.

Output a markdown table, one row per distinct factual claim you extracted and checked:

| # | Source | Claim (quote or close paraphrase) | Symbol I opened (file + function/type) | What the code actually does | VERDICT |

VERDICT: MATCH / MISMATCH / UNVERIFIED (say why you could not check).
Minimum 25 rows unless the scope genuinely contains fewer checkable claims —
in that case say how many it contained and why.

For every MISMATCH, below the table:
  CLAIM SAYS / CODE DOES (file + symbol) / REFUTATION ATTEMPT (what you tried to
  make the finding go away and why it survived) / SEVERITY HIGH|MEDIUM|LOW.

Close with: "Checked N claims: X match, Y mismatch, Z unverified."

- Before reporting a MISMATCH, try to REFUTE it — check other call sites and callers.
- Do NOT invent mismatches to look productive. An all-MATCH table is acceptable;
  the TABLE is not optional, because it is the only evidence that you checked.
- Do NOT report style, wording, missing sections, or code defects — only
  claim-says-X / code-does-Y.
EOF
    ;;
*)
    usage
    ;;
esac

PROMPT="${PREAMBLE}
${MODE_RULES}

## Task
$(cat "$BRIEF")"

# REVIEW_DRY_RUN=1 → print the assembled prompt and stop. It exists so that it can be
# VERIFIED that the guard really is in the prompt, without spending a whole run. The claim
# "the line is in the script" does not prove it made it into the prompt.
if [ -n "${REVIEW_DRY_RUN:-}" ]; then
    printf '%s\n' "$PROMPT"
    exit 0
fi

echo "→ agy ${MODE} | repo ${REPO_ABS} @ ${HEAD_SHA} | model ${MODEL}${EFFORT:+ | effort ${EFFORT}}" >&2

if [ -n "$OUT" ]; then
    # `set -e` above this block is a trap: both an agy failure and a `grep` with no match below
    # end the script BEFORE a single line of diagnostics is printed. Verified 26.7.2026 with a stub —
    # an empty run ended with exit 1 without a single line of explanation. Same pattern as
    # `set +e` in sol-review.sh.
    set +e
    agy -p "$PROMPT" --add-dir "$REPO_ABS" --model "$MODEL" \
        ${EFFORT:+--effort "$EFFORT"} \
        --mode plan --print-timeout "$TIMEOUT" > "$OUT" 2>&1
    rc=$?
    set -e
    # Despite --mode plan and the instruction above, agy sometimes writes the
    # deliverable into its own brain/scratch dir and replies with just a path.
    # A short output containing such a path is a stashed run, not a failed one.
    # The threshold "< 20 lines" was a bad discriminator: on 27.7.2026 a stashed report arrived
    # as a 21-line summary („Vytvořil jsem pro tebe … [dokument](file:///…)" [I created … for
    # you … [document](file:///…)]), so the recovery did not fire and 94 lines of material lay
    # unnoticed in the brain directory. What decides is the PRESENCE of a path into the brain
    # directory, not the length of the reply — when that path is there and the file is longer
    # than what arrived, it is a stashed deliverable.
    stashed=$(grep -oE '/[^ )"]*antigravity-cli/brain/[^ )"]*\.md' "$OUT" | head -1 || true)
    if [ -n "$stashed" ] && [ -f "$stashed" ]; then
        if [ "$(wc -l < "$stashed" | tr -d ' ')" -gt "$(wc -l < "$OUT" | tr -d ' ')" ]; then
            echo "→ deliverable stashed in brain dir, recovering: ${stashed}" >&2
            cp "$stashed" "$OUT"
        fi
    fi
    lines=$(wc -l < "$OUT" | tr -d ' ')
    echo "→ exit ${rc}, ${lines} lines → ${OUT}" >&2

    # An empty run MUST fail loudly. On 26.7.2026 agy returned exit 0 and a single line
    # "jetski: no output produced — a tool required the command permission…", because
    # at the LAST step it tried to write the report to /tmp. Before that it had opened 81 files
    # in 106 steps and threw all of it away. Exit 0 on empty output is worse than a
    # crash: the caller reads it as "it ran".
    if grep -qiE 'no output produced|auto-denied|required the "?command"? permission' "$OUT" \
       || [ "$lines" -le 2 ]; then
        echo "error: the run produced no report (${lines} lines)." >&2
        sed -n '1,3p' "$OUT" | sed 's/^/       | /' >&2
        echo "       Most common cause: agy tried to write the output to a file and the write was" >&2
        echo "       auto-denied. You will find the work in the conversation DB:" >&2
        echo "         ls -t ~/.gemini/antigravity-cli/conversations/*.db | head -1" >&2
        echo "       Do NOT ADD writing to the allow-list — the audit is meant to be read-only." >&2
        exit 3
    fi
    # Coverage is VERIFIED, not merely demanded. The brief has numbered items and survey mode
    # prescribes verbatim headings for them + a coverage ledger; on 26.7.2026 agy ignored both
    # and returned its own structure — while the enforcement was right there in the prompt.
    # The prompt cannot be tightened any further (that is fortune-telling), but it can be checked
    # mechanically: pull the numbered headings out of the brief and check that they are in the reply.
    if [ "$MODE" = "survey" ]; then
        missing=0; total=0
        while IFS= read -r n; do
            total=$((total + 1))
            grep -qE "^#{1,4} *$n\." "$OUT" || missing=$((missing + 1))
        done < <(grep -oE '^#{1,4} *[0-9]+\.' "$BRIEF" | grep -oE '[0-9]+' || true)
        if [ "$total" -gt 0 ] && [ "$missing" -gt 0 ]; then
            echo "warn: ${missing}/${total} numbered items of the brief have no heading of their own in the reply." >&2
            echo "      The output is usable, but it CANNOT tell you what was skipped." >&2
            echo "      Pull the coverage from the conversation DB (see skills/llm-review/SKILL.md)." >&2
        fi
        grep -qiE 'coverage ledger|ledger' "$OUT" \
            || echo "warn: coverage ledger missing — the list of opened files is only in the DB." >&2
    fi
    exit $rc
else
    agy -p "$PROMPT" --add-dir "$REPO_ABS" --model "$MODEL" \
        ${EFFORT:+--effort "$EFFORT"} \
        --mode plan --print-timeout "$TIMEOUT"
fi
