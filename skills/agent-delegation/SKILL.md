---
name: agent-delegation
description: "Handing multi-phase implementation work to an agent (fable) and getting it back verified — plan first, implementer's brief, 5-hour limit gating with claude-usage.sh, safe stopping points, and per-claim acceptance. Load BEFORE delegating implementation, and when a delegated run must survive a usage-limit reset."
---

# Delegating implementation to an agent

Companion to `audit-briefing` (how to brief someone who **looks** for defects). This file is about
briefing someone who **changes code** — the inverse job, with the inverse brief.

Written 6.8.2026 after a full day of delegated implementation across two limit windows; every rule
below is something that day cost or nearly cost.

---

## 0. The shape

```
plan (mine)  →  implementer's brief  →  agent works in its own worktree
                                     →  limit gate between phases
                                     →  agent reviews its OWN diff and resolves it  (§5b, always)
                                     →  I verify per claim, by running
                                     →  merge  →  teardown (worktree AND its DerivedData)
```

**The plan is written before the agent is spawned, and it is a file in the repo** — not prose in a
prompt. The agent reads it, updates its status as it goes, and the next person inherits both.

## 1. Independent analysis: never hand over your own diagnosis

When you want a second opinion rather than a second pair of hands, the brief must not contain what
you think the answer is. Give the artifact and the repo, ban the rationale documents
(`KNOWN_BUGS.md`, `AUDIT_BACKLOG.md`, `CHANGELOG.md` — see `audit-briefing` §1), and ask for the
root cause plus a reproduction.


**Where an independent analysis is worth the tokens:** when the fix is cheap but being wrong about
the cause is expensive. Not for mechanical work.

## 2. The implementer's brief — seven sections, all of them load-bearing

1. **The plan, by path.** "Read it in full before touching anything. Follow it; do not redesign it."
2. **Isolation.** Its own worktree, its own branch, `git add` explicit paths, **push nothing**.
   The main checkout is shared.
3. **The limit gate.** §3 below.
4. **Scope.** Which phases are in, which are explicitly out. Commit after each phase, once *that
   phase's own verification* has passed.
5. **Settled decisions — do not revert, do not re-litigate.** List them. An agent that re-opens a
   decision costs a round trip and usually loses the reason the decision existed.
6. **What must not be smuggled in.** No refactors beyond the plan, no "while I was there" cleanups,
   no fixing the underlying bug when the task is to build the instrument, and — always, explicitly
   — **no TestFlight upload, no `fastlane`**. That needs consent it does not have.

7. **The self-review loop (§5b).** Always. A numbered section, never an aside.

Then say how the work will be judged (§5). An agent told the acceptance criteria up front produces
evidence instead of prose.

## 3. The 5-hour limit gate

```bash
~/.claude/scripts/claude-usage.sh 90     # threshold in % utilization, default 95
```

Reads the authoritative `api.anthropic.com/api/oauth/usage` — the same data `/usage` shows (token
from the Keychain, 60 s cache in `~/.claude/cache/oauth-usage.json`).

| exit | meaning | action |
|---|---|---|
| 0 | every window below threshold | run the next phase |
| 1 | **any window at/above threshold** | finish the current step, commit, stop, report the reset time |
| 2 | no reading | do not guess — ask |

- 🔴 **Threshold 99 for fable** (the operator's decision, 6.9.2026). Run the check as
  `claude-usage.sh 99`, so a reading in the nineties is the GO it is meant to be. Running it with
  the old 90 returns `VERDICT: PAUSE` on a window the operator wants used.
  - The old number was **90**, chosen so an implementation delegation could finish its in-flight
    step and commit before the window closed — a unit costs roughly 10–20 points. That reasoning is
    about *writing* code and does not transfer to a *review*, which is short, leaves no
    half-finished tree, and is safe to have cut off. The effect of the old gate was that the last
    tenth of fable's weekly window went unused every week.
  - **When the window really is nearly gone, delegate anyway and say so in the brief:** ask for
    priority order, and for a report of what was covered and what was not, rather than trimming the
    scope yourself (the operator, same day).
- **There are THREE windows, not two, and the third is the one fable eats.** The script reads the
  `limits` **array**, not the named `five_hour` / `seven_day` fields:

  | `kind` | what `/usage` calls it |
  |---|---|
  | `session` | Current session (5 h) |
  | `weekly_all` | Current week, all models |
  | `weekly_scoped` | **Current week (Fable)** |

  `weekly_scoped` appears nowhere in `five_hour`/`seven_day`, so a version of this gate that checks
  only those two reports "OK to continue" while the model you are actually delegating to is out of
  quota. Found 6.8.2026 by comparing `/usage` output against the script's own — the script said two
  windows, `/usage` showed three. Iterating the array also survives new buckets appearing.
- **Which window tripped decides what waiting achieves.** A `session` trip clears in hours; a weekly
  one clears in days. The script prints every window with its own reset time and names the highest.
- ⚠️ **Never read this script's exit code through a pipe** (`| tail`, `| head`) — you get the pipe's
  status. Run it bare, then check `$?`. This cost a wrong reading twice in one day.
- `ccusage` cannot answer this. It infers a ceiling from the highest usage seen in previous blocks;
  that is an estimate, not the quota. It *is* right about time remaining in the block.

### Safe stopping points — define them in the plan, not in the moment

Stop only at a phase boundary, where:

1. the tree is clean or the work is committed,
2. deployed services and shipped clients are in a **mutually compatible** state,
3. the plan file records what is done and what is next.

Never stop between an edit and its deploy, between a deploy and its smoke test, or with a
half-edited `project.pbxproj`. Cut the phases so each ends somewhere safe.

## 4. Phase ordering that survives an interruption

- **Server before client** whenever the client sends something new. A worker that names its accepted
  fields explicitly drops unknown ones **silently** — deploy it first, or lose a whole round of data
  and not notice.
- **Backward compatibility is a constraint with a test**, not an intention: the exact payload the
  shipped client sends today must still produce today's exact record. Prove it with a control
  mutation — remove one existing field and watch the test go red.
- **Never mutate production to prove a test bites.** Use `wrangler versions upload` and drive the
  mutation against the preview URL.
- **Test writes must be self-identifying** (`source: "compat-test"`). A test row that cannot be told
  from a real one poisons the very signal the work exists to measure — and deleting it afterwards
  does not fix the daily aggregate that already counted it.

## 5. Acceptance — verify per claim, by running

An agent's report is a set of hypotheses, including the ones that say "verified". Check the ones
where being wrong is expensive:

- **Re-run the tests yourself**, and run the **mutation matrix** — which changed sites does the suite
  actually guard? A green suite is not protection it does not give — write down which changed sites
  the matrix left unguarded.
- **Build every target the change touches.** `swift test` runs on the host — it proves nothing about
  a 32-bit watch slice. The watch device scheme is the Watch app's own scheme with
  `-destination 'generic/platform=watchOS'`; the iOS app's scheme rejects that destination and
  prints a destination list instead, so the filter matches nothing and the pipeline exits 0.
- **Check the pbxproj didn't change target membership** if files moved.
- **Check what the agent deployed and when** (`wrangler deployments list`), not what it says it
  deployed.
- **Check what it wrote into shared state** — production KV, logs, memory files.
- Grep every device list, version list, or "all N sites" claim. Fable's quality varies; its wrong
  claims look exactly like its right ones.

**A verification step has a classifier, and the classifier is unverified code.** Before trusting a
matrix of results, run the two cases whose answers you already know — one that must pass, one that
must fail.

## 5b. 🔴 STANDARD: the agent reviews its own diff before handing it back

**This is not optional and not per-task. Every implementation delegation carries it** (the operator,
31.8.2026). The agent's last phase is always:

```
implement  →  sol review of ITS OWN net diff  →  resolve the findings  →  re-review
              (max 3 iterations, then stop and report what is still open)
```

Put it in the brief as a numbered section, not as an aside — an agent reads "also consider
reviewing" as optional and skips it.

**Why it belongs to the agent and not to me.** A review round I run afterwards costs a full
hand-back, a context rebuild and a second delegation; the agent still holds the diff, the
reasoning and the worktree, so the same round costs it almost nothing. And the pairing is the
point: `llm-review` measured five rounds on one build where **rounds 1–3, fixes written by me,
each introduced a new defect the next round found**, and the first clean round was the one where
the reviewer wrote the patch. Handing the agent both roles keeps that loop inside one context
instead of across three.

**What the brief has to say, or the loop degrades into theatre:**

- **Which wrapper**, with the quota caveat: `codex-quota.sh` reporting LOW while its reset time is
  in the PAST is an **invalid** reading, not a low one — probe the CLI before paying for API
  tokens.
- **The agent writes the brief itself**, and the brief must name the baseline SHA, ask for
  distinct optics, require `file`+symbol citations, require an attempt to REFUTE each finding
  before it is reported, and grant explicit permission to find nothing.
- **Never a hand-rolled `codex exec`** — the wrapper injects the ban on reading rationale
  documents, and without it the reviewer rationalises the author instead of checking them
  (`audit-briefing` §1). That matters doubly here: the author IS the agent being reviewed.
- **Accept per claim, not per reviewer**, and reject out loud with a reason. A reviewer's
  *approval* is a hypothesis too — it reasons about a diff, it cannot execute.
- **Bound the iterations** and require a report of what is still open. An unbounded loop either
  burns the quota or converges on agreement rather than on correctness.

⚠️ **This does not replace my own acceptance pass (§5).** The agent reviewing itself and me
verifying by running are different instruments: the review reasons about the diff, my pass runs
the mutation matrix and builds the targets `swift test` cannot reach. Two reviews are not a
substitute for one execution.

## 6. Traps that cost time on the real run

| Trap | What it looks like |
|---|---|
| `setsid` does not exist on macOS | a `nohup setsid …` launcher fails silently into `/dev/null`; you then read a **stale log** and report a build that never started. 32 minutes. Verify a launch three ways: first log line is *your own* marker, the process is alive, the log grows. |
| The Bash tool caps at 600 000 ms | a long archive gets killed mid-compile. Not a build failure — check the log for a verdict line before diagnosing. |
| An empty filter result is a third state | `grep` finding nothing because the command never ran looks identical to success. Count the success lines and assert `>= 1`. |
| `wrangler kv key list` truncates silently | Use the REST API. |
| The `xcodebuild-lock` hook matches your **text** | it blocks a command that merely mentions `xcodebuild` (a grep pattern, a heredoc writing a script) while one runs. Do not work around it — wait, or reword. |

## 6b. 🔴 Teardown — the worktree AND the DerivedData it created

**The delegation is not finished when the branch is merged.** An agent worktree leaves behind a
DerivedData directory of its own, and **nothing removes it — not `git worktree remove`, not the
merge, not Xcode.** Xcode keys DerivedData by workspace PATH, so every worktree gets a fresh one
the first time a build runs in it.


**Measured 30.8.2026:** four agent worktrees in one day, ~4.9 GB each, on top of the main
checkout's 8.2 GB. Together with earlier rounds that day the volume went from comfortable to
**89 % full and close to taking the machine down**, and the user had to ask for the cleanup.
Nobody had done anything wrong — the step simply did not exist in this file.

### The order matters, and one step is easy to lose

```
merge → verify by SHA → CAPTURE the DerivedData mapping → remove worktree → remove its DerivedData
```

🔴 **Capture the mapping BEFORE removing the worktree.** The only thing tying a DerivedData hash
to a worktree is `WorkspacePath` in its `info.plist`, and the moment the worktree is gone that
path is dead — indistinguishable from every other stale directory. Take the list first:

```bash
D=~/Library/Developer/Xcode/DerivedData
for d in $D/*-*; do
  WP=$(/usr/libexec/PlistBuddy -c "Print :WorkspacePath" "$d/info.plist" 2>/dev/null)
  case "$WP" in */.claude/worktrees/*) echo "$(basename $d)  $(du -sh "$d"|cut -f1)  $WP";; esac
done
```

**Identify by `WorkspacePath`, never by date or by size.** A removed worktree leaves a
freshly-dated directory, and the active project's is routinely the oldest one there.

### Before removing anything

1. **No build may be live.** Check with a pattern that does not contain the literal word
   `xcodebuild` — the `xcodebuild-lock` hook matches your own COMMAND TEXT and will block you:
   `ps -Ao comm= | grep -c "xcodebuil"`.
2. **Prove the commits are safe by SHA, never on a tool's word.**
   `git merge-base --is-ancestor $(git -C <wt> rev-parse HEAD) origin/main` — the removal warning
   compares against the LOCAL branch ref, which is routinely behind the remote.
3. **Check the worktree is clean** (`git -C <wt> status --short`) and that no live session holds
   it (`lsof +D <wt>` — SourceKit is fine, a `claude` process is not).

### Removing

```bash
git worktree remove <path>                       # or --force once you have proven the SHA
for d in <the hashes you captured>; do
  WP=$(/usr/libexec/PlistBuddy -c "Print :WorkspacePath" "$D/$d/info.plist" 2>/dev/null)
  case "$WP" in */.claude/worktrees/*) rm -rf "$D/$d";;
                *) echo "REFUSING $d — not a worktree: $WP"; exit 1;; esac
done
```

**Make the script refuse rather than trust your reading of the list** — the guard above is the
whole point of the loop.

⚠️ `rm -rf` half-succeeds on a Debug product that was ever RUN: `Contents/_MASReceipt/receipt` is
`root:wheel`, a small shell survives, and every later sweep keeps calling it live. Count first —
`find "$D/$d" -user root | wc -l` — and finish with `sudo` if it is non-zero. Agent worktrees that
only ever built `generic/platform=…` have none *(verified 30.8.2026: 0 root-owned files across
three of them)*.

⚠️ A worktree that ran a Debug build also leaves **LaunchServices registrations**, and macOS can
then serve that copy instead of the installed app. `lsregister -dump | grep -c "worktrees/agent-.*/Build/Products/Debug/"`
before you delete the path; unregister those products (`lsregister -u <path>`, verified by a re-count —
the command returns non-zero even when it worked) before the path goes. Archive-style builds
register nothing *(verified 30.8.2026: 0)*.

### Say it in the brief

The agent cannot clean up after itself — its worktree is alive while it runs, and it must not
touch the shared checkout. **Teardown is the delegator's job**, so it belongs in your own
follow-up, not in the agent's instructions. Asking the agent to report its DerivedData hash costs
nothing and saves the lookup.

## 7. When not to delegate

- Trivial mechanical edits — the brief costs more than the work.
- Anything where you cannot state the acceptance criteria before the agent starts. If you cannot say
  what would make you reject it, you are not delegating, you are hoping.
- Work that must touch the shared checkout's branch.
