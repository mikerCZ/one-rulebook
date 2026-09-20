#!/bin/bash
# G9: Claims need evidence.
#
# Blocks `git commit` when a STAGED ADDED line contains a universal/negative claim
# without an inline evidence token.
#
# Rationale (CLAUDE.md, "A claim carries its evidence"): unverified claims in comments and
# CHANGELOG entries are arguments for why a change is correct, not descriptions of what the
# code does. Four successive prose rules failed to stop them; this is the mechanical half.
#
# Scope — deliberately narrow, to keep false positives survivable:
#   * added lines only (`^+`), never context or removed lines
#   * only comment lines (// # * <!--) and lines in .md files
#   * only whole words, both EN and CS
#
# Escape hatch: put [claims-ok] in the commit message.
#
# NOTE: this hook cannot see justifications that carry no risky word ("X is fine because Y").
# Those are the second and larger class and remain a human check — see CLAUDE.md.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

echo "$COMMAND" | grep -qE 'git\s+commit' || exit 0
echo "$COMMAND" | grep -q '\[claims-ok\]' && exit 0

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -n "$CWD" ] && cd "$CWD" 2>/dev/null

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Added lines from the staged diff, tagged with their file.
# -c core.quotePath=false: with the default, a non-ASCII path arrives as "\304\233…" in quotes, the
# `+++ b/` header no longer names the file and the .md rule silently skips it (review, 20.9.2026).
DIFF=$(git -c core.quotePath=false diff --cached --no-renames -U0 2>/dev/null)
[ -z "$DIFF" ] && exit 0

HITS=$(echo "$DIFF" | awk '
  /^\+\+\+ b\// { file = substr($0, 7); next }
  /^\+/ {
    line = substr($0, 2)
    # SCOPE: code comments, CHANGELOG and project docs — i.e. where a JUSTIFICATION for a change
    # gets written. Deliberately NOT CLAUDE.md / SKILL.md / memory: those are rule text, where
    # "never do X" is an imperative, not a claim about how the code behaves. Blocking those would
    # fire on every rule and train me to pass [claims-ok] by reflex, which kills the hook.
    if (file ~ /CLAUDE\.md$/ || file ~ /SKILL\.md$/ || file ~ /(^|\/)memory\//) next
    is_md = (file ~ /\.md$/)
    is_comment = (line ~ /^[[:space:]]*(\/\/|#|\*|<!--)/)
    if (!is_md && !is_comment) next
    # already carries evidence → fine.
    #
    # cs-ok — the alternation below is a PATTERN, not prose: it has to spell the Czech marker
    # words to match them at all.
    #
    # They are STEMS, not whole words, because Czech declines them. The list held `hypoteza` in
    # the nominative alone, so marking a sentence as a hypothesis in any other case did not
    # count, and the hook then blocked the exact wording its own option (c) asks for
    # (measured 22.8.2026 by running this condition over the four cases of that one word: one
    # passed, three were blocked). Same shape for the three verbs beside it.
    # "reproduced" belongs here as much as "verified" does: CLAUDE.md states the whole rule as
    # "a fix is two observations" and calls the first one reproducing the failure. Leaving it out
    # blocked exactly the sentences that carried the strongest evidence (5.9.2026).
    if (tolower(line) ~ /(verified|ověřen|overen|measured|změřen|zmeren|reproduc|reprodukov|derivation|odvozen|hypothesis|hypotéz|hypotez)/) next

    # "read-only" is an access mode, not a claim that something happens ONLY somewhere — but the
    # word boundary [^a-z] accepts the hyphen, so every mention of it was blocked. It cost two
    # commits on 5.9.2026, and the fix has to stay narrow: a general "ignore any hyphen before
    # the word" would also wave through "admin-only" and "internal-only", which ARE claims.
    # So a short list of access-mode compounds is removed from the copy being matched, and
    # nothing else is.
    low = tolower(line)
    # tolower() leaves accented capitals alone under LC_ALL=C (review, 20.9.2026); normalise the
    # ones the Czech patterns can start with, so the guard does not depend on the locale.
    gsub(/Á/, "á", low); gsub(/É/, "é", low); gsub(/Í/, "í", low); gsub(/Ý/, "ý", low)
    gsub(/Š/, "š", low); gsub(/Ž/, "ž", low); gsub(/Ě/, "ě", low); gsub(/Č/, "č", low)
    # Git flags spelled with that suffix (--ff-only, --only) are the same shape; added 20.9.2026
    # after --ff-only in a moved comment was flagged.
    gsub(/read-only|write-only|append-only|readonly|read only sandbox|--ff-only|--only|gemini-vertex-only/, " ", low)

    # The Czech patterns are matched against `low` too, like the English ones: a sentence-initial
    # "Jediná" / "Všechny" / "Žádný" did not match the lowercase patterns (measured 20.9.2026 with
    # five probe lines while checking a GLM-5.2 finding that blamed the bracket expressions of BSD awk
    # — those match). The explicit normalisation above also covers a non-UTF-8 locale.
    if (low ~ /(^|[^a-z])(only|never|always|none|unconditional|unconditionally|behavior-preserving|behaviour-preserving)([^a-z]|$)/ ||
        low ~ /(all [0-9]+ (sites|places|call))/ ||
        low ~ /(jedin[áéýí]|jediný|všechn[ayoi]|žádn[ýáéoí]|nikdy|vždy)/) {
      printf "  %s\n    %s\n", file, substr(line, 1, 150)
    }
  }
')

[ -z "$HITS" ] && exit 0

{
  echo "BLOCKED: the staged diff contains a CLAIM with no evidence."
  echo ""
  echo "$HITS"
  echo ""
  echo "Every such sentence must either:"
  echo "  (a) carry its evidence inline — '(verified: <command | file:line | date>)'"
  echo "  (b) be reworded into a description that claims nothing, or"
  echo "  (c) be marked as an inference / hypothesis."
  echo ""
  echo "False positive? Add [claims-ok] to the commit message."
} >&2
exit 2
