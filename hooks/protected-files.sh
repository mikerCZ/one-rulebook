#!/bin/bash
# G1: files that must not be edited through the Edit/Write/apply_patch tools.
#
# The list of protected basenames comes from ~/.claude/protected-files.txt (one basename per
# line, `#` comments allowed; the path is overridable with PROTECTED_FILES_LIST). The original
# entry, and the reason the hook exists: a ~122k-line generated localisation file full of
# multi-byte characters (measured 4.8.2026: 121713 lines), on which the Edit tool crashes and
# Write rewrites the whole file. Allowed methods for such a file: sed insert, or Python
# str.replace() through Bash.
#
# 🔴 EXTENDED 5.9.2026 — the hook was blind to Codex.
# It read tool_input.file_path and nothing else (measured 5.9.2026: absent from every Codex
# payload logged that day). Codex sends an apply_patch envelope in tool_input.command
# and no file_path at all, so a Codex edit of the file returned 0 (measured: Claude input -> 2,
# Codex input -> 0, both against the then-current script). Both shapes now go through
# lib/hook-targets.py, which also names both halves of a rename and every file in a multi-file
# patch. A plain shell command (sed, python) carries no patch envelope and yields no targets —
# that is the ALLOWED path and stays allowed.
#
# Fail-closed: a payload the parser cannot read (exit 3) falls back to a raw match over the whole
# input, because "no targets" and "unreadable" arrive at the caller as the same empty list.
# An unreadable or empty list file protects nothing and says so on stderr, once per call.

INPUT=$(cat)
HERE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
LIB="$HERE/lib"
# The list: an explicit override, else ~/.claude/protected-files.txt (one list for every profile
# of this user), else the copy next to this script's real location (a symlinked install).
if [ -n "${PROTECTED_FILES_LIST:-}" ]; then
  LIST="$PROTECTED_FILES_LIST"          # an explicit override that is missing stays missing (warned below)
else
  LIST="$HOME/.claude/protected-files.txt"
  [ -f "$LIST" ] || LIST="$(dirname "$HERE")/protected-files.txt"
fi

NAMES=$(grep -vE '^\s*(#|$)' "$LIST" 2>/dev/null | sed 's/[[:space:]]*$//')
if [ -z "$NAMES" ]; then
  echo "protected-files: $LIST is missing or empty — nothing is protected" >&2
  exit 0
fi

TARGETS=$(printf '%s' "$INPUT" | python3 "$LIB/hook-targets.py" 2>/dev/null)
PRC=$?

HIT=""
if [ $PRC -eq 0 ]; then
  # basename match against every target of the payload
  HIT=$(printf '%s\n' "$TARGETS" | cut -f1 | awk -F/ '{print $NF}' | grep -F -x -f <(printf '%s\n' "$NAMES") | head -3)
  WHY="target"
else
  HIT=$(printf '%s' "$INPUT" | grep -o -F -f <(printf '%s\n' "$NAMES") | head -1)
  WHY="unparsed payload mentioning"
fi

if [ -n "$HIT" ]; then
  {
    echo "BLOCKED: $(printf '%s' "$HIT" | tr '\n' ' ' | sed 's/ *$//') is a protected file (see $LIST) and must not be edited through the Edit/Write/apply_patch tool."
    echo "  $WHY: $(printf '%s' "$HIT" | tr '\n' ' ')"
    echo "Use Bash with 'sed insert' or Python str.replace()."
  } >&2
  exit 2
fi

exit 0
