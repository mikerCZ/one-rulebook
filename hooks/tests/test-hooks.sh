#!/bin/bash
# Both-direction test for all global hooks. Kept in a file so the probe strings never appear on a
# Bash tool command line, where the hooks under test would block the test itself.
H="${CLAUDE_HOME:-$HOME/.claude}/hooks"
pass=0; fail=0
t() { # t <expected-rc> <hook> <json> <label>
  rc=$(printf '%s' "$3" | "$H/$2" >/dev/null 2>&1; echo $?)
  if [ "$rc" = "$1" ]; then echo "  ✅ $4"; pass=$((pass+1))
  else echo "  ❌ $4 — expected rc=$1, got rc=$rc"; fail=$((fail+1)); fi
}
c() { jq -nc --arg c "$1" '{tool_input:{command:$c}}'; }
f() { jq -nc --arg f "$1" '{tool_input:{file_path:$f}}'; }
# Codex shapes. Measured 5.9.2026 by logging the hook's own stdin during a real `codex exec` run:
# tool_name is "apply_patch", and the measured tool_input held one key, {command: "*** Begin Patch
# ... *** End Patch"};
# paths inside the envelope are relative to the payload's cwd, and Bash calls arrive as
# tool_name "Bash" with tool_input.command — the Claude alias, so the Bash hooks need no change.
px() { jq -nc --arg c "$1" --arg d "${2:-/x}" '{tool_name:"apply_patch",cwd:$d,tool_input:{command:$c}}'; }
w()  { jq -nc --arg f "$1" --arg t "$2" '{tool_name:"Write",tool_input:{file_path:$f,content:$t}}'; }
pw() { jq -nc --arg c "$1" --arg d "${2:-/x}" '{tool_name:"apply_patch",cwd:$d,tool_input:{command:$c}}'; }
BP="*** Begin Patch"; EP="*** End Patch"

SEC="LOGS_""API_KEY"
DEL="--de""lete"
UA="User-""Agent"

echo "── G1 protected-files (list-driven, 20.9.2026) ──"
PL=$(mktemp); printf '# comment\n\nsecret-ledger.md\nlarge_generated.py \n' > "$PL"
if [ -x "$H/protect-generate-strings.sh" ]; then   # the private shim for the pre-20.9.2026 wiring
  rc=$(printf '%s' "$(f /x/large_generated.py)" | PROTECTED_FILES_LIST="$PL" "$H/protect-generate-strings.sh" >/dev/null 2>&1; echo $?)
  if [ "$rc" = "2" ]; then echo "  ✅ shim blocks a listed name"; pass=$((pass+1)); else echo "  ❌ shim blocks a listed name — got rc=$rc"; fail=$((fail+1)); fi
  rc=$(printf '%s' "$(f /x/other.py)" | PROTECTED_FILES_LIST="$PL" "$H/protect-generate-strings.sh" >/dev/null 2>&1; echo $?)
  if [ "$rc" = "0" ]; then echo "  ✅ shim allows another .py"; pass=$((pass+1)); else echo "  ❌ shim allows another .py — got rc=$rc"; fail=$((fail+1)); fi
fi
tp() { # tp <expected-rc> <json> <label> — protected-files.sh with the fixture list
  rc=$(printf '%s' "$2" | PROTECTED_FILES_LIST="$PL" "$H/protected-files.sh" >/dev/null 2>&1; echo $?)
  if [ "$rc" = "$1" ]; then echo "  ✅ $3"; pass=$((pass+1)); else echo "  ❌ $3 — expected rc=$1, got rc=$rc"; fail=$((fail+1)); fi
}
tp 2 "$(f /x/large_generated.py)"          "blocks a listed name (trailing space in the list tolerated)"
tp 2 "$(f /y/deep/secret-ledger.md)"        "blocks a second listed name by basename"
tp 0 "$(f /x/secret-ledger.md.bak)"         "does not block a name that merely contains a listed one"
tp 0 "$(f /x/other.py)"                     "allows an unlisted file"
tp 2 "$(px "$BP
*** Update File: docs/secret-ledger.md
@@
-a
+b
$EP")"                                       "blocks a Codex apply_patch on a listed name"
tp 0 "$(c 'sed -i "" "s/a/b/" large_generated.py')" "allows a shell edit (no patch envelope)"
rc=$(printf '%s' "$(f /x/large_generated.py)" | PROTECTED_FILES_LIST=/nonexistent "$H/protected-files.sh" 2>&1 >/dev/null | grep -c 'nothing is protected')
if [ "$rc" = "1" ]; then echo "  ✅ a missing list warns instead of failing silently"; pass=$((pass+1)); else echo "  ❌ a missing list warns instead of failing silently — got $rc warnings"; fail=$((fail+1)); fi
rm -f "$PL"

echo "── G2 check-secrets-in-llm ──"
t 2 check-secrets-in-llm.sh "$(c "curl https://api.openai.com/v1 -d '{\"$SEC\":\"a\"}'")"  "blocks secret to openai"
t 2 check-secrets-in-llm.sh "$(c "curl https://api.z.ai/v4 -d '{\"$SEC\":\"a\"}'")"        "blocks secret to z.ai (was a gap)"
t 2 check-secrets-in-llm.sh "$(c "curl https://api.anthropic.com/v1 -d '{\"$SEC\":\"a\"}'")" "blocks secret to anthropic (was a gap)"
t 0 check-secrets-in-llm.sh "$(c "curl https://api.openai.com/v1 -d '{\"prompt\":\"hi\"}'")" "allows a clean prompt"
t 0 check-secrets-in-llm.sh "$(c "curl https://example.com -d '{\"$SEC\":\"a\"}'")"        "ignores a non-LLM host"
t 0 check-secrets-in-llm.sh "$(c "# note: api.openai.com and $SEC are mentioned here")"    "ignores a comment mention"

echo "── G3 conventional-commits ──"
t 2 conventional-commits.sh "$(c 'git commit -m "Fix: something"')"   "blocks capitalised Fix:"
t 2 conventional-commits.sh "$(c 'git commit -m "Add: something"')"   "blocks Add:"
t 0 conventional-commits.sh "$(c 'git commit -m "fix: something"')"   "allows fix:"
t 0 conventional-commits.sh "$(c 'git commit -m "feat(scope): thing"')" "allows feat(scope):"

echo "── G5 xcodebuild-lock (was DEAD) ──"
# The "allows" case asks about the machine, not about the hook: if a real build is running
# right now the correct answer is 2, and asserting 0 would report the guard as broken.
# Seen on 5.9.2026, when a concurrent session had one running.
if pgrep -x xcodebuild >/dev/null 2>&1; then
  echo "  ⏭  allows when none running — SKIPPED, a real build is running (pid $(pgrep -x xcodebuild | head -1))"
else
  t 0 xcodebuild-lock.sh "$(c 'xcodebuild -scheme A build')"            "allows when none running"
fi
t 0 xcodebuild-lock.sh "$(c '# xcodebuild must never run twice')"     "ignores a comment mention"
t 0 xcodebuild-lock.sh "$(c 'echo hello')"                            "ignores unrelated command"

echo "── G6 rsync-no-delete (rewritten: require a seatbelt, not ban the flag) ──"
t 2 rsync-no-delete.sh "$(c "rsync -avz $DEL a/ b:/c/")"                              "blocks delete with no --max-delete"
t 0 rsync-no-delete.sh "$(c "rsync -avz $DEL --max-delete=25 --exclude=stats/ a/ b:/c/")" "allows delete WITH a cap"
t 0 rsync-no-delete.sh "$(c "rsync -avz --dry-run $DEL a/ b:/c/")"                     "allows a dry run (was blocked before)"
t 0 rsync-no-delete.sh "$(c "rsync -avz -n $DEL a/ b:/c/")"                            "allows -n short form"
t 0 rsync-no-delete.sh "$(c 'rsync -avz a/ b:/c/')"                                    "ignores a sync without delete"
t 2 rsync-no-delete.sh "$(c "rsync -avz --delete-after a/ b:/c/")"                     "also covers --delete-after"
t 0 rsync-no-delete.sh "$(c "rsync -avz --delete-after --max-delete=5 a/ b:/c/")"      "…with a cap"
t 0 rsync-no-delete.sh "$(c "# rsync with $DEL is forbidden")"                         "ignores a comment mention"
t 0 rsync-no-delete.sh "$(c "git commit -m 'docs: rsync $DEL notes'")"                 "ignores a commit message"

echo "── G7 grok-user-agent ──"
t 2 grok-user-agent.sh "$(c 'curl https://api.x.ai/v1/chat -d "{}"')"          "blocks call without UA"
t 0 grok-user-agent.sh "$(c 'curl -A "Mozilla/5.0" https://api.x.ai/v1/chat')' " "allows call with -A"
t 0 grok-user-agent.sh "$(c "curl -H '$UA: M' https://api.x.ai/v1/chat")"      "allows call with header"
t 0 grok-user-agent.sh "$(c '# api.x.ai needs a User-Agent')"                  "ignores a comment mention (was a false positive)"

echo "── G8 gemini-vertex-only (warns, never blocks) ──"
t 0 gemini-vertex-only.sh "$(c 'curl https://generativelanguage.googleapis.com/v1beta/x')" "warns but allows AI Studio"
t 0 gemini-vertex-only.sh "$(c 'curl https://aiplatform.googleapis.com/v1/x')"             "silent on Vertex"

echo "── commit-message exemption (new) ──"
t 0 grok-user-agent.sh  "$(c "git commit -m 'docs: api.x.ai needs a UA'")"          "grok: commit message is prose"
t 2 rsync-no-delete.sh  "$(c "rsync -avz $DEL a/ b:/c/ && git status")"             "rsync: uncapped call still blocked"


echo "── G1 protected-files — Codex apply_patch shape ──"
# Before 5.9.2026 every one of these returned 0: the hook read tool_input.file_path, which
# Codex does not send. The list is a fixture, so the block does not depend on the installed list.
GS="large_generated.py"
PL2=$(mktemp); printf '%s\n' "$GS" > "$PL2"; export PROTECTED_FILES_LIST="$PL2"
t 2 protected-files.sh "$(px "$BP
*** Update File: loc/$GS
@@
-a
+b
$EP")"                                                        "blocks a patch updating it"
t 2 protected-files.sh "$(px "$BP
*** Add File: $GS
+x
$EP" /repo)"                                                  "blocks a patch adding it (relative path + cwd)"
t 2 protected-files.sh "$(px "$BP
*** Delete File: loc/$GS
$EP")"                                                        "blocks a patch deleting it"
t 2 protected-files.sh "$(px "$BP
*** Update File: a/other.py
@@
-a
+b
*** Update File: loc/$GS
@@
-c
+d
$EP")"                                                        "blocks a MULTI-FILE patch where it is not first"
t 2 protected-files.sh "$(px "$BP
*** Update File: loc/old_strings.py
*** Move to: loc/$GS
@@
-a
+b
$EP")"                                                        "blocks a RENAME onto the protected name"
t 2 protected-files.sh "$(px "$BP
*** Update File: loc/$GS
*** Move to: loc/renamed.py
@@
-a
+b
$EP")"                                                        "blocks a RENAME away from the protected name"
t 0 protected-files.sh "$(px "$BP
*** Update File: a/other.py
@@
-a
+b
*** Add File: b/third.swift
+let x = 1
$EP")"                                                        "ALLOWS a multi-file patch that never names it"
t 0 protected-files.sh "$(px "$BP
*** Add File: docs/notes.md
+the file $GS must be edited with sed
$EP")"                                                        "ALLOWS a patch that only MENTIONS it in content"
t 0 protected-files.sh "$(c "sed -i '' '100i\\    x' loc/$GS")"   "ALLOWS the sanctioned sed edit"
t 0 protected-files.sh "$(c "python3 -c \"open('$GS')\"")"        "ALLOWS the sanctioned python edit"
t 0 protected-files.sh "$(c 'echo hello')"                        "ignores an unrelated shell command"
t 2 protected-files.sh "{not json at all $GS"                     "fail-closed on an UNREADABLE payload naming it"
t 0 protected-files.sh "{not json at all}"                        "unreadable payload that does not name it still passes"

unset PROTECTED_FILES_LIST; rm -f "$PL2"

echo "── G10 instructions-in-english — Codex apply_patch shape ──"
CZ_DOC="tento soubor musi byt cesky protoze to tak chci"
t 2 instructions-in-english.sh "$(px "$BP
*** Update File: skills/x/SKILL.md
@@
+$CZ_DOC
$EP")"                                                        "blocks Czech added to a SKILL.md by patch"
t 0 instructions-in-english.sh "$(px "$BP
*** Update File: skills/x/SKILL.md
@@
+this line is written in plain english
$EP")"                                                        "allows English added to a SKILL.md by patch"
t 0 instructions-in-english.sh "$(px "$BP
*** Update File: notes/scratch.txt
@@
+$CZ_DOC
$EP")"                                                        "ignores a file type outside its scope"
t 2 instructions-in-english.sh "$(px "$BP
*** Update File: a/ok.md
@@
+fine
*** Update File: CLAUDE.md
@@
+$CZ_DOC
$EP")"                                                        "blocks on the SECOND file of a multi-file patch"
t 2 instructions-in-english.sh "$(w /x/CLAUDE.md "$CZ_DOC")"  "still blocks the Claude Write shape"

echo "── G9 claims-need-evidence ──"
# This hook reads the STAGED diff of the repo named by the payload's cwd, so the fixture needs a
# real repo. Built in a scratch dir and torn down at the end.
CR=$(mktemp -d "${TMPDIR:-/tmp}/claims-fixture.XXXXXX")
git -C "$CR" init -q .
cl() { # cl <expected-rc> <file> <line> <label>
  printf '%s\n' "$3" > "$CR/$2"
  git -C "$CR" add "$2" >/dev/null 2>&1
  j=$(jq -nc --arg c 'git commit -m "docs: x"' --arg d "$CR" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}')
  rc=$(printf '%s' "$j" | "$H/claims-need-evidence.sh" >/dev/null 2>&1; echo $?)
  if [ "$rc" = "$1" ]; then echo "  ✅ $4"; pass=$((pass+1))
  else echo "  ❌ $4 — expected rc=$1, got rc=$rc"; fail=$((fail+1)); fi
  git -C "$CR" rm -q --cached "$2" >/dev/null 2>&1; rm -f "$CR/$2"
}
ONLY="on""ly"
cl 2 a.md "This runs $ONLY on the main branch."                 "blocks a bare claim in a .md"
cl 2 "důkaz.md" "This runs $ONLY on the main branch."           "blocks a bare claim in a NON-ASCII file name (core.quotePath, review 20.9.2026)"
cl 2 cz1.md "Jediná cesta je tahle."                              "blocks a sentence-initial Czech universal (matched against the lowercased line since 20.9.2026)"
cl 2 cz2.md "Všechny volání jsou pokryté."                        "blocks všechny"
cl 2 cz3.md "Žádný test to nechytí."                              "blocks žádný"
cl 0 cz4.md "Tohle je běžná věta bez univerzálního slova."       "ALLOWS an ordinary Czech sentence"
LC_ALL=C cl 2 cz5.md "ŽÁDNÝ TEST TO NECHYTÍ."                     "blocks an UPPERCASE Czech universal under the C locale"
LC_ALL=C cl 0 cz6.md "BĚŽNÁ VĚTA VELKÝMI PÍSMENY."                "ALLOWS an ordinary uppercase Czech sentence under the C locale"
cl 0 b.md "The sandbox is read-$ONLY for the reviewer."         "ALLOWS read-only (was a false positive)"
cl 0 c.md "The wrapper is write-$ONLY."                         "ALLOWS write-only"
cl 2 d.md "That endpoint is admin-$ONLY."                       "still blocks admin-only, which IS a claim"
cl 0 e.md "This runs $ONLY on main (verified 5.9.2026)."        "ALLOWS a claim that carries evidence"
cl 0 g.md "This runs $ONLY on main (reproduced 5.9.2026)."      "ALLOWS reproduced as evidence too"
cl 0 f.txt "This runs $ONLY on the main branch."                "ignores a file type outside its scope"
rm -rf "$CR"


echo
echo "  pass=$pass  fail=$fail"
[ "$fail" = "0" ] || exit 1
