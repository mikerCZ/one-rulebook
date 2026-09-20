#!/bin/bash
# G10: Instruction files and code comments are written in English.
#
# Blocks Write/Edit when the content being written puts Czech prose into:
#   * the instruction layer — CLAUDE.md, skills/**/*.md, memory/*.md   (whole content checked)
#   * source files — .swift .js .ts .py .sh .dart                      (COMMENT LINES only)
#
# Why a hook and not a rule: on 4.8.2026 I wrote the rule "moved content is translated" and then
# broke it twice within twenty minutes, each time by matching the host file's language. A prose
# rule did not survive its own author for one session.
#
# ⚠️ DETECTION: diacritics alone are a PROXY, not the thing. Czech written without them
# ("nejdriv zmer kvotu") would sail straight through, and that is a trivial way to defeat the
# hook by accident or otherwise. So there are two independent detectors:
#   1. words carrying Czech diacritics
#   2. unambiguous Czech function words that have no English collision (ktery, protoze, musi, …)
# Either one firing twice blocks the write.
#
# Only the NEW content is inspected (Write `content`, Edit `new_string`) — never the rest of the
# file. That enforces "new and edited content in EN" without forcing a bulk rewrite of an existing
# Czech file, which is banned for its own good reason: a batch translation re-stamps every claim
# the text carries without anyone verifying it.
#
# Czech inside backticks and "quotes" is allowed — a quoted localised string is evidence of what a
# system returns, and translating it destroys the evidence. In source files, string literals are
# stripped before checking for the same reason.
#
# Escape hatch: put cs-ok anywhere in the content being written.
#
# 🔴 EXTENDED 5.9.2026 — the hook read tool_input.file_path, a field absent from every Codex
# payload measured that day (five apply_patch calls logged during real codex exec runs).
# Codex puts an apply_patch envelope in tool_input.command; lib/hook-targets.py turns either
# shape into (path, new-content) pairs, so one patch touching several files is checked file by
# file and a rename is checked under its new name too.
#
# NOTE: no literal backtick may appear anywhere below. The Python block runs inside a command
# substitution, where bash parses backticks as command substitution and dies with "unexpected
# EOF" — which silently turned every test green on the first version of this hook. Uses \x60.

INPUT=$(cat)
LIB="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib"

check_one() {
  FILE="$1"; NEW="$2"

  MODE=""
  case "$FILE" in
    */CHANGELOG.md|*/MEMORY-ARCHIVE.md)                 return 0 ;;
    # My own tooling: the echo strings ARE the message to the agent, not data — check everything.
    # Added 4.8.2026 after I wrote diacritic-free Czech into the messages of this very hook.
    */.claude/hooks/*|*/.claude/scripts/*)              MODE="doc" ;;
    */CLAUDE.md|*/AGENTS.md|*/skills/*.md|*/memory/*.md) MODE="doc" ;;
    *.swift|*.js|*.ts|*.py|*.sh|*.dart)                 MODE="code" ;;
    *)                                                  return 0 ;;
  esac

  [ -z "$NEW" ] && return 0

RESULT=$(NEW="$NEW" MODE="$MODE" python3 <<'PYEOF'
import os, re, sys

text = os.environ["NEW"]
mode = os.environ["MODE"]
if "cs-ok" in text:
    sys.exit(0)

if mode == "code":
    # Only comment lines. A Czech UI string is not a comment and must not be touched.
    lines = []
    for ln in text.split("\n"):
        s = ln.strip()
        m = re.match(r"^(//+|#+|/\*|\*(?!/)|<!--)\s*(.*)", s)
        if m:
            lines.append(m.group(2))
    text = "\n".join(lines)
    if not text.strip():
        sys.exit(0)

CZ = "áčďéěíňóřšťúůýž"
CZ += CZ.upper()
W = r"[\w" + CZ + r"]"

# Strip what may legitimately stay Czech: fenced code, inline code, quoted strings, links, paths.
t = re.sub(r"```.*?```", " ", text, flags=re.S)
t = re.sub(r"\x60[^\x60]*\x60", " ", t)
t = re.sub(r'"[^"]*"', " ", t)
t = re.sub(r"'[^']*'", " ", t)
t = re.sub(r"„[^“]*“", " ", t)
t = re.sub(r"\[\[[^\]]*\]\]", " ", t)
t = re.sub(r"\]\([^)]*\)", " ", t)
t = re.sub(r"\S*/\S*", " ", t)

# Proper nouns that are legitimately Czech even inside an English file. Detector 1 matches a
# word that carries a diacritic (the `dia` regex below requires a CZ character), so an entry
# without one is dead weight (the list used to carry seven such names). Your own — a project whose name carries a diacritic, say — go into
# ~/.claude/instructions-allowed-words.txt, one per line; that file is optional and private.
ALLOW = {"čnb", "české", "česko", "čr"}
try:
    with open(os.path.expanduser("~/.claude/instructions-allowed-words.txt"), encoding="utf-8") as fh:
        ALLOW |= {ln.strip().lower() for ln in fh if ln.strip() and not ln.startswith("#")}
except OSError:
    pass

# --- detector 1: diacritics ---
dia = [w for w in re.findall(W + r"*[" + CZ + r"]" + W + r"*", t) if w.lower() not in ALLOW]

# --- detector 2: Czech function words with no English collision ---
# Deliberately excludes anything that is also an English word (vice, tak, ma, pro, do, to, a, i,
# on, sen, plan, post, pas, led, byt) and anything under 3 characters.
STOP = {
    "ktery", "ktera", "ktere", "kterou", "kterych", "kterym", "kteryho", "kterym",
    "protoze", "takze", "pokud", "jestli", "jelikoz", "nebot",
    "musi", "musis", "muze", "muzes", "nemusi", "nemuze", "melo", "mela", "mely",
    "vsechny", "vsechno", "vsechna", "vsech", "zadny", "zadna", "zadne", "zadnou",
    "nejdriv", "nejprve", "jeste", "vzdycky", "vzdy", "nikdy", "porad", "znovu",
    "neni", "nema", "nejsou", "nebyl", "nebude", "bude", "budou", "byla", "bylo", "byly",
    "podle", "mezi", "kdyz", "aby", "aniz", "misto", "kvuli", "behem", "dokud", "zatimco",
    "mensi", "vetsi", "vice", "mene", "spis", "radeji", "pouze", "jenom", "proto", "tedy",
    "zmena", "zmenit", "zmeny", "oprava", "opravit", "opravy", "soubor", "soubory", "radek",
    "radku", "chyba", "chyby", "hodnota", "hodnoty", "vystup", "vstup", "spustit", "spusti",
    "prvni", "druhy", "treti", "tohle", "tenhle", "tady", "ovsem", "avsak", "potreba",
    "nasledne", "pote", "predtim", "jsem", "jsme", "jste", "jsou", "sice", "napriklad",
    "vsak", "tim", "tomu", "toho", "tato", "tento", "tyto", "techto", "takovy", "takove",
}
STOP -= {"vice"}   # English "vice versa" / "vice president"
words_l = [w.lower() for w in re.findall(r"[A-Za-z]{3,}", t)]
stop_hits = [w for w in words_l if w in STOP]

hits = list(dict.fromkeys(dia + stop_hits))
if len(hits) >= 2:
    print(" ".join(hits)[:200])
    sys.exit(1)
sys.exit(0)
PYEOF
)
PRC=$?

  [ $PRC -ne 1 ] && return 0

WHAT="an instruction file"
[ "$MODE" = "code" ] && WHAT="a code comment"
{
  echo "BLOCKED: $WHAT is written in ENGLISH."
  echo ""
  echo "  file:  $FILE"
  echo "  Czech words in the NEW content: $RESULT"
  echo ""
  echo "Applies to CLAUDE.md, SKILL.md, memory *.md, hooks/ and scripts/, and to COMMENT"
  echo "LINES in sources — and only to the content you are writing right now. You do NOT"
  echo "have to rewrite the rest of an existing Czech file: a batch translation re-stamps"
  echo "every claim the text carries without anyone verifying it."
  echo ""
  echo "Both diacritics AND diacritic-free Czech are detected. Dropping the accents does"
  echo "not get you through, and is not worth attempting."
  echo ""
  echo "A quoted localised string belongs in backticks or \"quotes\" — the hook does not"
  echo "look there; in sources only comment lines are checked, never string literals."
  echo "Deliberate Czech elsewhere: add cs-ok."
} >&2
  return 2
}

# One record per target file: <path>\t<base64 of the new content>.
PARSED=$(printf '%s' "$INPUT" | python3 "$LIB/hook-targets.py" 2>/dev/null)
[ $? -ne 0 ] && exit 0   # unreadable payload: this hook is advisory about language, not a gate

RC=0
while IFS=$'\t' read -r P B64; do
  [ -z "$P" ] && continue
  CONTENT=$(printf '%s' "$B64" | base64 --decode 2>/dev/null)
  check_one "$P" "$CONTENT" || RC=2
done <<< "$PARSED"

exit $RC
