#!/bin/bash
# Fixture suite for codex-sync.sh. Every case runs the REAL script against a throwaway tree via
# the CS_* root overrides, so nothing here can touch the live configuration.
#
# Written 5.9.2026 after a Codex review reproduced three defects that --check reported green on,
# because --check inspected the happy path alone: a failed backup still deleted its target,
# the concurrency lock truncated the pid it was about to read, and --apply returned 0 after
# refusing to write.
S="${CLAUDE_HOME:-$HOME/.claude}/scripts/codex-sync.sh"
SRC_ROOT="$(cd "$(dirname "$S")/.." && pwd)"
pass=0; fail=0
chk() { # chk <label> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "  ✅ $1"; pass=$((pass+1))
  else echo "  ❌ $1 — expected [$2], got [$3]"; fail=$((fail+1)); fi
}

new_root() { # prints a fresh fixture root with a minimal but VALID configuration
  R=$(mktemp -d "${TMPDIR:-/tmp}/cs-fixture.XXXXXX")
  mkdir -p "$R/.claude/skills/demo" "$R/.claude/hooks" "$R/.claude/codex/rules" \
           "$R/.claude/codex/safe-bin" "$R/.claude/agy" "$R/.codex/rules" "$R/.codex/hooks" \
           "$R/.codex/safe-bin" "$R/.agents/skills" "$R/.gemini/antigravity-cli"
  echo "# rulebook" > "$R/.claude/CLAUDE.md"
  echo "## delta"   > "$R/.claude/codex/AGENTS.codex.md"
  echo "SKILL"      > "$R/.claude/skills/demo/SKILL.md"
  # hooks.json is RENDERED from the template (20.9.2026); the fixture furnishes the template plus
  # the one hook script it names, so the rendering, the hook link and the rules links are exercised.
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"'"'"'__CODEX_HOME__/hooks/demo.sh'"'"'","timeout":5}]}]}}\n' > "$R/.claude/codex/hooks.template.json"
  printf '#!/bin/bash\nexit 0\n' > "$R/.claude/hooks/demo.sh"; chmod +x "$R/.claude/hooks/demo.sh"
  echo "# rules"    > "$R/.claude/codex/rules/default.rules"
  echo "# local"    > "$R/.claude/codex/rules/local.rules"
  # a safe-bin TEMPLATE (rendered on install) next to a plain wrapper (copied), plus local.env
  printf '#!/bin/bash\n# owner=__GITHUB_OWNER__ home=__HOME__ user=__USER__ projects=__PROJECTS__\n' > "$R/.claude/codex/safe-bin/demo-wrapper.sh.template"
  printf '#!/bin/bash\nexit 0\n' > "$R/.claude/codex/safe-bin/plain-wrapper.sh"
  printf 'CS_GITHUB_OWNER=fixture-owner\nCS_LAUNCH_LABEL=fixture.label\nCS_CODEX_PROFILE=fixture-dev\n' > "$R/.claude/codex/local.env"
  cp "$SRC_ROOT/codex/codex-sync.plist.template" "$R/.claude/codex/codex-sync.plist.template"   # the REAL template (review, 20.9.2026)
  echo "stub"       > "$R/.claude/codex/home-AGENTS.md"
  : > "$R/.gemini/settings.json";                       cp "$R/.gemini/settings.json" "$R/.claude/agy/gemini-settings.json"
  : > "$R/.gemini/antigravity-cli/settings.json";       cp "$R/.gemini/antigravity-cli/settings.json" "$R/.claude/agy/antigravity-cli-settings.json"
    # The permission assertions are about a real machine; give the fixture a config that satisfies
  # them, so a failure here means the SCRIPT changed, not that the fixture is under-furnished.
  cat > "$R/.codex/config.toml" <<TOML
default_permissions = "fixture-dev"
approval_policy = "on-request"
approvals_reviewer = "auto_review"
"$R/.claude/scripts" = "read"
"$R/.claude/skills" = "read"
"$R/.claude/hooks" = "read"
"$R/.private_keys" = "deny"
"$R/.ssh" = "deny"
[desktop]
external-agent-import-sync-enabled = true
[hooks.state."$R/.codex/hooks.json:pre_tool_use:0:0"]
trusted = true
TOML
  echo "$R"
}
run() { # run <root> <mode> [extra env assignments...]  -> prints exit code, output to $OUT
  local r="$1" m="$2"; shift 2
  OUT=$(env CS_HOME="$r" CLAUDE_HOME="$r/.claude" CODEX_HOME="$r/.codex" AGENTS_DIR="$r/.agents" \
        BACKUP_DIR="$r/backups" REPORT="$r/report.json" LOCK="$r/lock" CS_NOTIFY=0 "$@" \
        bash "$S" "$m" 2>&1); local rc=$?
  printf '%s\n' "$OUT" > "$r/last-run.log"   # so a red case can be read afterwards
  echo $rc
  return $rc                                  # so a caller that needs $OUT can read rc from $? instead
}

echo "── happy path ──"
R=$(new_root)
rc=$(run "$R" --apply); chk "--apply on a fresh root returns 0" "0" "$rc"
rc=$(run "$R" --check); chk "--check is green afterwards"      "0" "$rc"
chk "the skill became a link" "yes" "$([ -L "$R/.agents/skills/demo" ] && echo yes || echo no)"
chk "hooks.json was rendered with the real CODEX_HOME" "yes" "$(grep -qF "'$R/.codex/hooks/demo.sh'" "$R/.claude/codex/hooks.json" && echo yes || echo no)"
chk "no placeholder survives in the rendering" "0" "$(grep -c __CODEX_HOME__ "$R/.claude/codex/hooks.json")"
chk "the hook named by the template became a link" "yes" "$([ -L "$R/.codex/hooks/demo.sh" ] && echo yes || echo no)"
chk "default.rules is linked" "yes" "$([ -L "$R/.codex/rules/default.rules" ] && echo yes || echo no)"
chk "local.rules is linked too" "yes" "$([ -L "$R/.codex/rules/local.rules" ] && echo yes || echo no)"
chk "the safe-bin template was rendered under its plain name" "yes" "$([ -f "$R/.codex/safe-bin/demo-wrapper.sh" ] && echo yes || echo no)"
chk "the rendering carries local.env's owner and this home" "# owner=fixture-owner home=$R user=$(id -un) projects=$R/Projects" "$(sed -n 2p "$R/.codex/safe-bin/demo-wrapper.sh")"
chk "the rendered wrapper is executable" "yes" "$([ -x "$R/.codex/safe-bin/demo-wrapper.sh" ] && echo yes || echo no)"
chk "the plain wrapper was copied" "yes" "$(cmp -s "$R/.claude/codex/safe-bin/plain-wrapper.sh" "$R/.codex/safe-bin/plain-wrapper.sh" && echo yes || echo no)"
plist=$(env CS_HOME="$R" CLAUDE_HOME="$R/.claude" CODEX_HOME="$R/.codex" bash "$S" --render-plist)
chk "--render-plist substitutes the label" "fixture.label" "$(printf '%s' "$plist" | python3 -c 'import plistlib,sys; print(plistlib.loads(sys.stdin.buffer.read())["Label"])')"
chk "the login-shell command takes the script path as a positional argument" 'exec "$1" --apply' "$(printf '%s' "$plist" | python3 -c 'import plistlib,sys; print(plistlib.loads(sys.stdin.buffer.read())["ProgramArguments"][2])')"
chk "the script path is its own argument, home substituted" "$R/.claude/scripts/codex-sync.sh" "$(printf '%s' "$plist" | python3 -c 'import plistlib,sys; print(plistlib.loads(sys.stdin.buffer.read())["ProgramArguments"][4])')"
echo "── a hand-edited rendered wrapper is drift ──"
echo "edited" >> "$R/.codex/safe-bin/demo-wrapper.sh"
rc=$(run "$R" --check); chk "--check goes red on an edited rendered wrapper" "1" "$rc"
rc=$(run "$R" --apply); chk "--apply re-renders it" "0" "$rc"
chk "the edit is gone" "2" "$(wc -l < "$R/.codex/safe-bin/demo-wrapper.sh" | tr -d ' ')"

echo "── a root path with shell/sed metacharacters renders (review finding, 20.9.2026) ──"
# The first renderer used sed with | as its delimiter; a home containing | printed nothing with
# rc 0, and --apply would have written that empty rendering over hooks.json.
P=$(mktemp -d "${TMPDIR:-/tmp}/cs-pipe|amp&.XXXXXX"); R2=$(TMPDIR="$P" new_root)
rc=$(run "$R2" --apply); chk "--apply returns 0 with | and & in the root path" "0" "$rc"
chk "hooks.json carries the literal path" "yes" "$(grep -qF "$R2/.codex/hooks/demo.sh" "$R2/.claude/codex/hooks.json" && echo yes || echo no)"
chk "hooks.json is not empty" "yes" "$([ -s "$R2/.claude/codex/hooks.json" ] && echo yes || echo no)"
chk "the safe-bin rendering carries the literal path" "yes" "$(grep -qF "home=$R2" "$R2/.codex/safe-bin/demo-wrapper.sh" && echo yes || echo no)"

echo "── an unrenderable template is a failure, not an empty file ──"
R3=$(new_root); run "$R3" --apply >/dev/null
printf '   \n' > "$R3/.claude/codex/safe-bin/blank-wrapper.sh.template"     # renders to whitespace
rc=$(run "$R3" --apply); chk "--apply returns 1 on a template that renders to nothing" "1" "$rc"
chk "no target was written for it" "no" "$([ -e "$R3/.codex/safe-bin/blank-wrapper.sh" ] && echo yes || echo no)"
chk "the failure is named" "yes" "$(grep -q 'blank-wrapper.sh: template could not be rendered' "$R3/last-run.log" && echo yes || echo no)"
printf '#!/bin/bash\necho "unterminated\n' > "$R3/.claude/codex/safe-bin/broken-wrapper.sh.template"   # renders, but is not valid bash
rm -f "$R3/.claude/codex/safe-bin/blank-wrapper.sh.template"
rc=$(run "$R3" --apply); chk "--apply returns 1 on a rendering that fails bash -n" "1" "$rc"
chk "the broken rendering was not installed" "no" "$([ -e "$R3/.codex/safe-bin/broken-wrapper.sh" ] && echo yes || echo no)"

echo "── a first --apply on a machine with no ~/.codex yet (review finding, 20.9.2026) ──"
R4=$(new_root); rm -rf "$R4/.codex" "$R4/.agents"
rc=$(run "$R4" --check); chk "--check on a machine without ~/.codex returns 1" "1" "$rc"
chk "the missing config.toml is ONE finding, not eight" "1" "$(grep -c 'config.toml is missing' "$R4/last-run.log")"
chk "no 'no longer says' lines for a file that never existed" "0" "$(grep -c 'no longer says' "$R4/last-run.log")"
rc=$(run "$R4" --apply); chk "--apply creates the target directories and links the hooks" "yes" "$([ -L "$R4/.codex/hooks/demo.sh" ] && [ -f "$R4/.codex/safe-bin/demo-wrapper.sh" ] && echo yes || echo no)"

echo "── the plist rendering escapes XML metacharacters ──"
P2=$(mktemp -d "${TMPDIR:-/tmp}/cs-amp&lt.XXXXXX"); R5=$(TMPDIR="$P2" new_root)
out=$(env CS_HOME="$R5" CLAUDE_HOME="$R5/.claude" CODEX_HOME="$R5/.codex" bash "$S" --render-plist)
chk "the ampersand in the home path is escaped" "yes" "$(printf '%s' "$out" | grep -q '&amp;' && echo yes || echo no)"
chk "the rendering is well-formed XML" "yes" "$(printf '%s' "$out" | python3 -c 'import sys,xml.dom.minidom; xml.dom.minidom.parseString(sys.stdin.read())' 2>/dev/null && echo yes || echo no)"
chk "the decoded script path (with & in it) is one argument" "$R5/.claude/scripts/codex-sync.sh" "$(printf '%s' "$out" | python3 -c 'import plistlib,sys; print(plistlib.loads(sys.stdin.buffer.read())["ProgramArguments"][4])')"

echo "── the default lock path creates its cache directory (review finding, 20.9.2026) ──"
RL=$(new_root)
env CS_HOME="$RL" CLAUDE_HOME="$RL/.claude" CODEX_HOME="$RL/.codex" AGENTS_DIR="$RL/.agents" BACKUP_DIR="$RL/backups" CS_NOTIFY=0 bash "$S" --check >/dev/null 2>&1
chk "the default lock file was opened under cache/" "yes" "$([ -f "$RL/.claude/cache/codex-sync.lock" ] && echo yes || echo no)"
chk "the check reached the report" "yes" "$([ -f "$RL/.claude/cache/codex-sync-report.json" ] && echo yes || echo no)"

echo "── a hand-edited rendering is drift ──"
echo '{"hooks":{"PreToolUse":[]}}' > "$R/.claude/codex/hooks.json"
rc=$(run "$R" --check); chk "--check goes red on a hooks.json that is not the template's rendering" "1" "$rc"
rc=$(run "$R" --apply); chk "--apply re-renders and returns 0" "0" "$rc"
chk "the rendering is back" "yes" "$(grep -qF "'$R/.codex/hooks/demo.sh'" "$R/.claude/codex/hooks.json" && echo yes || echo no)"

echo "── P1: a failed backup must not delete the target ──"
R=$(new_root)
run "$R" --apply >/dev/null                       # establish the links
rm "$R/.agents/skills/demo"                       # the importer replaced it with a real copy…
mkdir -p "$R/.agents/skills/demo"
echo "local work nobody else has" > "$R/.agents/skills/demo/local-work.txt"
rm -rf "$R/backups"; : > "$R/backups"             # …and the backup path is now a FILE, so mkdir -p fails
rc=$(run "$R" --apply)
chk "the local file survives"      "yes" "$([ -f "$R/.agents/skills/demo/local-work.txt" ] && echo yes || echo no)"
chk "--apply reports failure"      "1"   "$rc"

# The pid-file lock case that used to sit here is gone with the pid protocol itself; the contract
# is now asserted against the OS lock further down ("the lock is an OS advisory lock").

echo "── P2: a refused write is not a repair ──"
R=$(new_root)
run "$R" --apply >/dev/null
echo "written by somebody else" > "$R/.codex/AGENTS.md"   # marker gone -> must be refused
# Not `rc=$(run …)`: that runs `run` in a subshell, so $OUT would still hold the FIRST apply's
# output — which is what this case read until 20.9.2026, when a fresh root began repairing ten
# items and `grep 'repaired 1'` matched "repaired 10" (measured: the case went red on the
# happy path's count, not on P2's behaviour).
run "$R" --apply >/dev/null; rc=$?
chk "--apply returns non-zero when it refused" "1" "$rc"
chk "the foreign file is untouched" "written by somebody else" "$(cat "$R/.codex/AGENTS.md")"
chk "no repair is claimed for the refused write" "no" "$(echo "$OUT" | grep -qE 'repaired [1-9]' && echo yes || echo no)"

echo "── the lock is an OS advisory lock, not a pid protocol ──"
# The mkdir version created the directory and wrote the pid in two steps; a second process that
# arrived in that window read no pid, called the lock orphaned, removed it and went in — and the
# first one's EXIT trap then deleted the live second's lock. Found by a Codex review 5.9.2026.
# What is asserted here is the contract, not the mechanism: a lock somebody else holds refuses,
# and a lock file left behind by a crash does not.
R=$(new_root); run "$R" --apply >/dev/null      # sync it first, so a 1 can only mean drift
HOLD=$(mktemp "${TMPDIR:-/tmp}/cs-holder.XXXXXX.sh")
cat > "$HOLD" <<'HOLDER'
exec 9<>"$1"
python3 -c 'import fcntl; fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)' || exit 1
echo ready > "$2"
sleep 6 9<&-        # the sleep must NOT inherit fd 9, or it outlives us holding the lock
HOLDER
bash "$HOLD" "$R/lock" "$R/held" & HP=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$R/held" ] && break; sleep 0.3; done
rc=$(run "$R" --check); chk "a lock held elsewhere refuses the run" "3" "$rc"
kill $HP 2>/dev/null; wait $HP 2>/dev/null; rm -f "$HOLD"
rc=$(run "$R" --check); chk "the lock is free once the holder is gone" "0" "$rc"
: > "$R/lock"                                   # a file left behind by a crash, locked by nobody
rc=$(run "$R" --check); chk "a leftover lock file does not block" "0" "$rc"

echo "── an unrepairable config finding is not in sync ──"
R=$(new_root)
run "$R" --apply >/dev/null
# portable in-place edit (BSD sed -i '' is not GNU sed -i)
python3 - "$R/.codex/config.toml" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read().replace('approvals_reviewer = "auto_review"','approvals_reviewer = "user"'); open(p,'w').write(s)
PY
rc=$(run "$R" --apply)
chk "--apply does not return 0 over a permission change" "1" "$rc"
chk "--apply does not claim in sync"  "no" "$(grep -q '^in sync' "$R/last-run.log" && echo yes || echo no)"
chk "the report counts it as unrepaired" "1" "$(python3 -c "import json;print(json.load(open('$R/report.json'))['unrepaired_count'])" 2>/dev/null)"
chk "the script did not edit config.toml" "yes" "$(grep -q 'approvals_reviewer = \"user\"' "$R/.codex/config.toml" && echo yes || echo no)"

echo "── a dangling project skill is a finding, not a skip ──"
R=$(new_root); run "$R" --apply >/dev/null
mkdir -p "$R/proj/.agents/skills" && : > "$R/proj/AGENTS.md"
( cd "$R/proj" && git init -q . && git -c user.email=x@y -c user.name=x commit -q --allow-empty -m "feat: x" ) 2>/dev/null
ln -s "$R/proj/.claude/skills/gone" "$R/proj/.agents/skills/broken"
OUT=$(env CS_HOME="$R" CLAUDE_HOME="$R/.claude" CODEX_HOME="$R/.codex" AGENTS_DIR="$R/.agents" \
      BACKUP_DIR="$R/backups" REPORT="$R/report.json" LOCK="$R/lock" CS_NOTIFY=0 CS_PROJECTS="$R/proj" \
      bash "$S" --check 2>&1); rc=$?
chk "--check goes red on a dangling project skill" "1" "$rc"
chk "the broken name is reported" "yes" "$(echo "$OUT" | grep -q 'broken' && echo yes || echo no)"

echo "── a project checkout is reported, never written to ──"
R=$(new_root); mkdir -p "$R/proj/.git"
( cd "$R/proj" && git init -q . && git -c user.email=x@y -c user.name=x commit -q --allow-empty -m "feat: x" ) 2>/dev/null
BEFORE=$(cd "$R/proj" && git rev-parse HEAD)
OUT=$(env CS_HOME="$R" CLAUDE_HOME="$R/.claude" CODEX_HOME="$R/.codex" AGENTS_DIR="$R/.agents" \
      BACKUP_DIR="$R/backups" REPORT="$R/report.json" LOCK="$R/lock" CS_NOTIFY=0 CS_PROJECTS="$R/proj" \
      bash "$S" --check 2>&1); rcc=$?
chk "--check goes red on a project with no AGENTS.md" "1" "$rcc"
chk "it is flagged as needing a human" "yes" "$(echo "$OUT" | grep -q 'NEEDS A HUMAN' && echo yes || echo no)"
OUT=$(env CS_HOME="$R" CLAUDE_HOME="$R/.claude" CODEX_HOME="$R/.codex" AGENTS_DIR="$R/.agents" \
      BACKUP_DIR="$R/backups" REPORT="$R/report.json" LOCK="$R/lock" CS_NOTIFY=0 CS_PROJECTS="$R/proj" \
      bash "$S" --apply 2>&1); rca=$?
chk "--apply does not fail over it"    "0" "$rca"
chk "--apply does not claim in sync"   "no"  "$(echo "$OUT" | grep -q '^in sync' && echo yes || echo no)"
chk "the project repo was not touched" "$BEFORE" "$(cd "$R/proj" && git rev-parse HEAD)"
chk "no AGENTS.md was created in it"   "no" "$([ -e "$R/proj/AGENTS.md" ] && echo yes || echo no)"

echo "── the JSON report must be written, not left stale ──"
# The report silently stopped updating once when the caller passed the wrong argument list: the
# python heredoc died and the previous file stayed, looking current. Assert the counts, not just
# that a file exists.
R=$(new_root)
run "$R" --apply >/dev/null
rm "$R/.agents/skills/demo"; mkdir -p "$R/.agents/skills/demo"; echo copy > "$R/.agents/skills/demo/SKILL.md"
run "$R" --apply >/dev/null
chk "report records the repair" "1" "$(python3 -c "import json;print(json.load(open('$R/report.json'))['repaired_count'])" 2>/dev/null)"
chk "report records no failure"  "0" "$(python3 -c "import json;print(json.load(open('$R/report.json'))['unrepaired_count'])" 2>/dev/null)"
R=$(new_root)
echo "written by somebody else" > "$R/.codex/AGENTS.md"
run "$R" --apply >/dev/null
chk "report records the refusal" "1" "$(python3 -c "import json;print(json.load(open('$R/report.json'))['unrepaired_count'])" 2>/dev/null)"

echo "── P2: a missing source is an error, not a repair ──"
R=$(new_root)
rm "$R/.claude/CLAUDE.md"
rc=$(run "$R" --apply); chk "--apply returns non-zero" "1" "$rc"

echo
echo "  pass=$pass  fail=$fail"
[ "$fail" = "0" ] || exit 1
