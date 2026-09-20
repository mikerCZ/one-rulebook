---
name: fix-series
description: "Running a plan that lands as many units over hours, unattended — the FULL lane (fable writes, astra audits, fable fixes, sol reviews, stop) and the LITE lane (a clean Opus agent writes, astra reviews the whole diff AND fixes, sol verifies after it, stop), when to switch between them, and the orchestrator's own acceptance pass with an independent mutation matrix. Also: measure before planning, findings triaged into fix-now vs list-at-the-end, the two handoff documents, the heartbeat monitor, and compact discipline. Load BEFORE starting the first unit of a multi-unit series."
---

# Running a multi-unit fix series

Load this when a plan splits into **units that land one at a time** and the work runs for hours,
usually unattended. Companion to `dev-flow` (tiering), `agent-delegation` (briefing one agent),
`audit-briefing` (briefing a reviewer) and `multi-session` (a peer in the repo). This file adds only
what those do not cover: **the loop across many units, and who is allowed to verify what.**

Written 6.9.2026 after one overnight run: six units landed, three review rounds each, and — the
number that matters — **every one of the four plans I wrote carried at least one false statement**.
Rules below with a measurement attached were paid for that night.

---

## 1. The two versions

| | **FULL** | **LITE** |
|---|---|---|
| orchestrates | Opus (you) | Opus (you) |
| writes the code | **fable** | **a CLEAN Opus agent** — never you yourself |
| who FINDS | `astra-review.sh` (read-only) | the writer's **own self-review**, then **astra over the whole net diff** (§1a) |
| who FIXES | fable | **`codex-fix.sh --astra`** — astra WITH write permission, in its own worktree, fixing what IT found |
| final review | `sol-review.sh` → **STOP** | `sol-review.sh` verifying what astra did → **STOP** |
| costs | `weekly_scoped` (fable) + Codex | Codex + `weekly_all`; **`weekly_scoped` untouched** |

🔴 **Never write the implementation yourself, in either version.** Your acceptance pass is only
independent if you did not author what it judges. That is the whole reason the clean-Opus lane
exists (the operator, 5.9.2026).

🔴 **`codex-fix.sh` is a FIXER, not a review, and getting this wrong leaves LITE with no finder.**
It **requires** a findings file (refuses a missing or empty one) and builds its prompt as
`RULES + "## FINDINGS TO FIX" + <the file>`. `--astra` selects the premium model **for the fixer**,
behind the same gate — a flag since 7.9.2026 (spelled `--human-asked` since 20.9.2026), because the env-var form cannot be
matched by a permission rule and the classifier had started refusing it. So astra IS in LITE — with write permission, in an isolated
worktree — but something else has to produce the list it consumes.

The script's own header says why this is not a flag on the review wrappers:

> A reviewer that writes reviews its own patch on the next pass. **Finder and fixer have to be two
> runs, or the second layer is gone** and the output looks exactly the same.

In FULL the finder is a separate `astra-review.sh` pass.

## 1a. 🔴 In LITE, astra reviews the WHOLE diff and fixes in the same pass

**The operator's correction, 7.9.2026, and it overrides the split the header above argues for.** The lane
as written left astra checking nothing: it was only a fixer, handed a list somebody else produced —
and because the writing agent resolves its own findings (`agent-delegation` §5b), that list can come
back empty, the script refuses an empty file, and **astra would not run at all.** On the unit that
prompted this, astra had already found a false safety claim in the plan that three of my own
readings had missed; leaving the strongest available reader out of the code review is not a saving.

**What the requirement actually is.** Not that finder and fixer are different runs — that an
**independent layer looks at the diff AFTER the fixer**. The header's sentence ("the second layer is
gone and the output looks exactly the same") is satisfied by sol running after astra and the
orchestrator running after sol. An extra read-only astra round before the fixer adds a round without
adding a layer; that was my first proposal and the operator rejected it for exactly that reason.

```
Opus agent writes  →  its own sol self-review (free, inside its context)
  →  astra reviews the WHOLE net diff and fixes in one pass
  →  sol verifies what astra did, independently
  →  the orchestrator's acceptance pass (§3e)
```

🔴 **The one thing that merge costs, and the sentence that buys it back.** Finding and fixing in one
pass removes the point where somebody decides **what should be fixed at all** — §3d's triage. Without
it the diff grows with backlog material and the acceptance pass judges a bigger change than was
commissioned. So the brief must say: **fix only regressions this block introduced and items that are
destructive AND reproduced AND newly reachable; LIST the rest and leave it alone.** The triage then
happens on that list, afterwards, by the orchestrator.

⚠️ **The input is neither a findings list nor "review everything".** `codex-fix.sh`'s rules run per
finding (reproduce → one-sentence failure → observe it gone → what stayed open) and it refuses an
empty file, so a vague instruction destroys its structure. Pass **numbered check questions over the
whole diff**, each with a reproduction and a verification — that keeps the script's shape while
handing astra the entire change.

Keeping the writer in both roles is deliberate: it **reproduces each finding by mutation before
accepting it** and rejects reviewer patches that pin a spelling. A fixer handed a list patches; it
does not triage.

⚠️ **Whatever the lane, run `codex-fix.sh --cleanup <worktree>` afterwards.** The run never commits,
pushes, merges or removes anything — the diff is the product — and its worktree keeps ~5 GB of
DerivedData until you take it.

## 2. When to switch FULL → LITE

The operator's rule: **at `weekly_scoped` ≥ 95 %, move to smaller blocks and to LITE.**

⚠️ **In practice the trigger fires earlier, and the arithmetic is worth doing.** `agent-delegation`
sets fable's own stop threshold at **99** (the operator raised it from 90 on 6.9.2026), so at 94 %
fable has five points — and a unit costs
roughly 10–20 (measured on three units: ≈ 10, ≈ 21, ≈ 13). A delegation that stops five points in
spends a whole brief on a stub and hands back half a unit. **Compute what the next unit costs before
delegating, not what the gate says.** If the answer is "fable cannot finish this", switch — and write
down that you did and why, because it is a reading of the rule rather than the rule.

```bash
~/.claude/scripts/claude-usage.sh 99     # BARE, read $? — never through a pipe
```

Three windows, and `weekly_scoped` is fable's. **It is per ACCOUNT** — measured 6.9.2026: `~/.claude`
read 87 % resetting 8.9., `CLAUDE_CONFIG_DIR=~/.claude-bp` read 91 % resetting 7.9., different values
*and different windows*. A concurrent lane on another profile cannot appear in your meter, so a jump
in yours is yours.

**Smaller blocks:** one failure sentence, ideally one function, and an explicit list of what the
block is **NOT** (see §4 R-rules). A block whose scope you cannot state negatively is too big.

## 3. The per-unit loop

```
measure  →  plan  →  delegate  →  reviews (per version)  →  MY acceptance  →  rebase
         →  MY docs  →  push verified by SHA  →  teardown  →  next unit
```

### 3a. Measure BEFORE planning — this is the phase people skip

🔴 **A triage row describes what HAPPENS. It is not a brief.** Four plans, four false statements, and
the same root each time: a sentence lifted out of a triage row into a plan changes genre without
changing words. Before writing any clause, say what should hold **instead** of what the row
describes — that sentence is a decision and needs its own evidence.

Concrete failures from one night: a unit claimed to close a finding that is unreachable from the
client for three independent reasons; a plan named four surfaces of which two never speak to the
subsystem at all, while the dashboard row had named the right one; a failure sentence written in the
present tense about a path that does not exist because the category it needs is never registered.

**Deliverable of this phase: a research note per block** that says what was measured, with
`file` + symbol, and states plainly where it **corrects the triage**. Every note written that night
corrected it.

⚠️ **Deduplicate by SYMBOL before writing, not after.** An ID grep over `KNOWN_BUGS.md` /
`AUDIT_BACKLOG.md` returns **zero** for a finding that is recorded, because rows name findings in
groups.
Grep the symbols. And settled
decisions sometimes live **only in a code comment** — one night's audit re-found a won't-fix whose
entire record was a boxed banner comment in a source file.

### 3b. Plan

Numbered decisions (`R1…Rn`) marked **settled — do not re-litigate**, a commit series with red/green
per commit, a named **control mutation that must NOT go red**, and an explicit "what this block is
not". ⚠️ Check the control is not a no-op: "pass the argument at the site that already passes it"
changes nothing. A usable control is *semantically identical, textually different*.

🔴 **Whenever the plan prescribes a CHECK, it must also name the input that would defeat a naive
version of it.** Otherwise you have handed the implementer the trap your own brief warns about, and
it will follow the prescription rather than the warning — twice in one run I wrote both into one
document, four sections apart, and the warning did not fire. A prescription of the form "pin that X
is called" is the commonest instance: it asks for a MENTION where the property is that X *decides*.

⚠️ **Every plan in this series carried at least one false statement — six for six.** Say so in the
brief (§3c) and expect the corrections back; they have been worth more than the implementations.

### 3c. Delegate

`agent-delegation` has the seven sections. Add these, all of which cost a round that night:

- **"Find what is wrong in this plan and bring the measurement."** Say the last N plans each carried
  a false statement. It works: agents found all of them.
- `--filter` matches the TYPE and the FILE, never a `@Suite` display name.
- **The completion-marker trap:** `sol-review.sh` requires the reviewer's last line to be a marker,
  and the brief that says so is echoed into the same log. Decide completion by `tail -1` or by the
  process being gone, never by grepping for the marker's presence.
- **Docs are never the agent's.** Status, CHANGELOG, dashboard rows and on-device queue rows are
  yours; say so, or you get two versions of them.

🔴 **Three brief defects that each cost a whole astra round on 16.9.2026 (rounds 5–6 of one unit, and round 4's conflict over a pinned test)** —
none of them was a code defect, and astra correctly STOPPED on each contradiction instead of guessing:

1. **Never declare a test "unchanged" without reading what it pins.**
   Read the assertions, then say which half is settled and what the other half must become.
2. **Never prescribe assertion values you did not measure.**
   Ask the fixer for the measured values first, or write the expectation as a property, not a number.
3. **Check a scenario is REACHABLE before calling it a coverage gap.**
   Trace the guards between the entry point and the line before
   briefing it as a defect (the acceptance-matrix rule "a surviving mutation is not automatically a hole" applies to
   your own briefs too).

### 3d. Reviews, and what a finding is

**Round budget — YOURS: `astra-review.sh` + `sol-review.sh` in FULL; `codex-fix --astra` (which
reviews and fixes, §1a) + `sol-review.sh` in LITE. No third round of yours without the operator's word.**
The writer's own self-review rounds (`agent-delegation` §5b) are separate and do not count against
that budget. ⚠️ Since 7.9.2026 they no longer FEED `codex-fix` in LITE — astra reads the whole diff
itself — but they stay mandatory, because a finding the writer resolves in its own context costs a
fraction of one resolved after a hand-back.

⚠️ **Do not let the fixer be the last thing that looked at the diff.** In LITE the sequence ends
`codex-fix` → **your** `sol-review.sh`, and that final read is the second layer: `codex-fix` wrote
the patch, so it cannot be the one that judges it.

🔴 **Your round must cover the writer's OWN fix commits, and the brief has to say so.** The writer's
self-review produces commits that nothing has looked at — in one unit six of eleven commits were
those fixes, and the last commit WAS the last round's output. `audit-briefing` §11 has the rule; what
this lane adds is that the obvious brief ("review the diff") aims the reviewer at the original change
instead. Name the earlier findings **by symbol**, say they are *claimed* fixed, and point the round
at what the fixes introduced.

Every finding is a **hypothesis until you reproduce it** — including the reviewer's approval of a
fix. And a reviewer's **fix** needs more verification than its finding: one night, astra's patch
discriminated two producers by `entityId` vs `entity_id`, i.e. by **letter case**.

🔑 **Read what a reviewer says about its own limits.** The best round that night stated plainly that
it could not run a Swift binary and would not present its checks as a test run. That sentence is
worth more than a confident one.

| what the review found | what happens |
|---|---|
| a **regression this block introduced** | **fix it** (the operator: "p2 regrese opravit" [p2: fix regressions]) |
| destructive **and** reproduced **and** newly reachable | **fix it**, even if pre-existing in mechanism |
| anything else | **list it** — one batch, at the very end |
| a settled decision re-found | say so out loud, do not re-litigate; the defect is in the triage |

### 3d-bis. Batch review rounds by INDEPENDENCE — one round per unit is not the unit of cost

Approved by the operator 7.9.2026, after they did the arithmetic out loud: a lane took about an hour per unit
the day before, and a list of eleven units therefore reads as eight hours. Their question was whether
to land every fix first and review once at the end.

🔴 **No — and today's own run is the measurement.** Eleven astra lenses over a tree carrying **two**
of my units found **three defects inside those two units**. Had eleven units landed first, those
three would have sat under nine more, and fixing the earliest would have meant re-verifying
everything built on top of it. This repo has already paid for that shape once: rounds 1–3 on one
build, each fix written between rounds introducing the defect the next round found.

**But one round per unit is not the alternative — it is just the other extreme.** The round should
attach to **independence**, not to a unit boundary:

| batch these together | never batch these |
|---|---|
| units with **no shared file and no shared mechanism** — a reviewer sees them as unrelated diffs | a unit that another unit builds on |
| units that are **two instances of ONE mechanism** — a reviewer seeing both is *better*, not worse | anything that changes the same record, row or contract twice |
| small, self-contained fixes with a verified patch already in hand | the CRITICAL of the series, whatever else is true of it |


🔑 **The second half of the saving is that WRITING parallelises inside a batch.** Units that qualify
for one review round are by construction file-disjoint, so their writers can run at the same time.
The gain is not only fewer rounds — it is three units being written at once.

⚠️ **State the cost rather than discovering it.** A finding against one member of a batch means
re-verifying its batch-mates, because they share a commit range. That is affordable exactly when the
independence was **measured** rather than assumed — which is the same check §5 already requires for
two parallel lanes, and it fails the same way: two units can be file-disjoint and still collide on
identifiers in a shared document.

🔴 **What does NOT batch: the orchestrator's own acceptance pass (§3e).** It stays per unit — its own
mutation matrix, its own forced build, its own suite run. It is the only instrument in the chain that
EXECUTES rather than reasoning about a diff, and on 7.9.2026 it was what revealed that a test fixture
of mine had asserted the right outcome from an input reality cannot produce. Collapsing it into one
matrix per round throws away exactly the aim that makes it work.

### 3e. 🔴 MY acceptance pass — never delegated, never taken from the agent's table

The agent's report is a set of hypotheses, *including the ones that say "verified"*.

```bash
swift test --disable-sandbox                 # bare, read $?
python3 <MY OWN matrix>                      # see below
```

**The matrix must aim somewhere the implementer's did not.** Theirs test behaviour; aim yours at
what behaviour cannot see — the telemetry vocabulary, a barrier's internals, a flag's readers. That
is how one night's matrices found two things three review rounds missed: an unreachable mutation
(which would have been a false finding) and a real hole in a flag the agent had introduced for
exactly that case and **described without pinning**.

Rules for the matrix, each paid for:

- Run it only on a **committed** tree — the restore is `git checkout --`.
- **Three states**: RED / GREEN / **BUILD-FAILED**. Never two.
- 🔴 **Score against the baseline's failing SET, never against zero.** Capture the set of failing test
  NAMES first; a row is RED only for a failure the baseline did not already have. An exit-code matrix
  over a red baseline reports every row RED and concludes *"all mutations caught"* — a green verdict
  from an instrument that saw nothing. It happened on a **wall-clock** assertion in a file the diff
  never touched; `swift test` runs suites in parallel and manufactures its own contention, so "wait
  for a quiet machine" is not a remedy and raising the constant only postpones. **Do not fix it by
  excluding the flaky test** — that hides the next real one.
- 🔴 **A sub-harness that refuses to run is a fourth state, not a RED.** The repo's own harnesses print
  `HARNESS VOID` / `GATE VOID` when an anchor no longer matches and exit with a code of their own —
  2 in the Python probes, 1 in the shell mutation scripts (measured 20.9.2026 over `scripts/`) — so
  read the MESSAGE. Collapsing that exit into "non-zero" throws away the one bit that matters, and
  the failure again resolves toward *"everything is caught"*.
- ⚠️ **A control over a line that a text-keyed harness anchors on is not a valid control** — any
  rewrite there legitimately voids it. Put controls where the anchors do not reach, and if a
  same-region control is impossible, write that down instead of reporting a false red.
- Assert every anchor occurs **exactly once** before mutating; a rotted anchor must report
  `NO-ANCHOR`, not silently no-op.
- At least one **control that must stay GREEN**.
- Prefer subtle mutations (inverted comparison, swapped source, off-by-one) to deletions — a
  deletion is the case the author already imagined.
- 🔴 **For every check the unit writes, write the input that would make it GREEN while the thing it
  guards is broken, and RUN it.** Across one series **eleven** checks passed for the wrong reason and
  **reading found none of them** — a spelling pin, a guard widened to another platform, a
  line-counting enumerator, a later overwrite of the same key, a discarded `find` status, an
  extension predicate, a prefix match, a count whose two operands came from one extraction, an
  "actions are non-empty" assertion that let a lock offer Open/Close, an example set that did not
  contain the case its assertion was about, and **a local variable shadowing the stored instance**,
  which would have shipped a whole unit inert while sixteen pins stayed green. Three shapes recur:
  **a count whose two sides come from one extraction**; **a predicate that decides what counts as an
  artifact by naming convention**; **a check that reads the presence of a call instead of the
  property that makes it work.** If no such input can be constructed, say that in the check's own
  comment — it is the only honest form of "this cannot be fooled".
- 🔴 **A surviving mutation is not automatically a hole.** Trace the reader: "the test is missing"
  and "the mutation has no effect" need different sentences. One night, one survivor was unreachable
  (proved by running a standalone replica over 8 adversarial inputs, 0 of which reached the branch)
  and another was a genuine multi-server defect.

**Build coverage:**

- `UP-TO-DATE` with zero `SwiftCompile` is a green marker over nothing → `rc=2 INCOMPLETE`.
- ⚠️ **A four-platform assertion needs TWO files when the changed file lives in one target** — the
  changed file for the target that carries it, plus a `Shared/` file for the rest. One file gives you
  either nothing about three platforms or nothing about your change.

### 3f. Rebase, docs, push, teardown

- **Verify on the MERGED tree, not on your branch** — suite *and* build, after the rebase. `origin/main`
  moved three times inside one hour that night.
- Re-read the **on-device queue identifier range from `origin/main` at the moment of writing**;
  foreign lanes take numbers (two collisions in one day).
- Stage explicit paths. **Push, then verify by SHA equality** (`git ls-remote --heads origin main`
  vs `git rev-parse HEAD`), never by exit code.
- Teardown: capture the DerivedData → `WorkspacePath` mapping **before** removing anything; make the
  removal script **refuse** rather than trust your reading, and prove it bites by pointing it at the
  other lane's directory first.

🔴 **From inside a worktree session most of that teardown cannot be run at all**, and the skill used
to prescribe commands the harness refuses: `git -C <another worktree>`, and any loop that hands a
runtime variable to `PlistBuddy` or `lsof`. Reading the branch refs through `git for-each-ref`
works (reading them as plain files went blind once git packed them — heartbeat.sh v3, 6.9.2026);
little else does. **So plan for the teardown to happen when the session is NOT inside a worktree, or to be
the owner's.** Capture the mapping anyway — it is the part that dies with the tree.

⚠️ **Two kinds of build output fill the disk and only one is where you look.** Besides
`~/Library/Developer/Xcode/DerivedData`, a repo can hold DerivedData under another name inside its
own gitignored `build/` (`build/sim`, `build/DerivedDataMac`). Judge those by **mtime plus "nothing
touched in the last two hours"**, confirm `git ls-files` returns nothing for the path, and leave the
`.xcarchive` siblings alone — they carry local dSYMs. A shared `ModuleCache.noindex` is regenerable
but the NEXT build uses it, so it fails the "no further build" test.

**Commit-hook mechanics (both cost a round):**

| hook | mechanism | working shape |
|---|---|---|
| `claims-need-evidence` | greps the **command text** | `-F <file>` hides `[claims-ok]` from it — put the subject in `-m` |
| `conventional-commits` | greedy sed takes the **LAST** `-m` | one `-m` for the subject, then `--amend -F <body file>` |

⚠️ Before **any** amend, assert `git diff --cached --name-only` is empty and read back the
changed-file count — an amend rebuilds from the index and will annex a peer's staged file silently.

⚠️ `[claims-ok]` needs a stated reason in the message. An unexplained one is indistinguishable from a
bypass. Fix your own unevidenced sentences first; excuse only what is genuinely someone else's
already-committed prose.

## 4. What goes to the operator, and when

🔴 **One batch, at the very end.** Not per unit, not per finding, and never as finding IDs or
symbols — as **short comprehensible questions with a recommended answer**.

Keep **two** documents, updated as you go, mirrored **outside the session scratchpad** (it is
session-scoped and does not survive):

| document | for | contains |
|---|---|---|
| `LANE-<x>-STATE.md` | the next session, or you after a compact | standing instructions, per-unit status with SHAs, the acceptance recipe, traps hit, quota table, what is in flight |
| `MORNING-LIST.md` | the operator | **a lead** (three sentences + "if you read only three things"), then: **A** decisions that are theirs with your recommendation · **B** named residues · **C** what you got wrong and how it was found · **D** what is left · **E** what ran on no device · **F** measured mechanisms |

**Section C is the most useful part of that document.** Fifteen entries after one night, and one
shape recurred in three of them. Write it honestly; it is what makes the rest trustworthy.

## 5. The monitor

🔴 **MANDATORY, AND NOT A JUDGEMENT CALL. Start it before the first unit, every time.** The operator,
8.9.2026: *"uprav monitor jako povinnost soucast, nesmis nad jeji vhodnosti uvazovat, proto tam je."*
[make the monitor a mandatory part; you must not weigh whether it is appropriate — that is why it is there]
There is no situation in which you get to decide it is redundant — that decision is not yours to
make, and the reason it is written this way is that it was made, once, and cost a night.

**What that cost, 7.–8.9.2026.** The skill was read at 21:47 and the heartbeat judged unnecessary,
on the reasoning that *the harness notifies me when an agent finishes, so a fifteen-minute tick adds
nothing.* That reasoning is true for agents and **false for anything detached** — and later the same
night a `codex-fix` run was launched with `nohup … & disown`, which by construction can never notify
anybody. It finished at 00:14. The orchestrator came back at **06:23**, six hours later, with sol,
the acceptance pass, the merge, the TestFlight round and the dashboards all still undone. Nothing was
broken; the night simply stopped, and nothing existed that could say so.

🔑 **The premise that fails is always the same one: "I will be told."** You are told about agents.
You are not told about a detached shell, a run whose parent exited, a review whose `.done` file
nobody polls, or a machine that quietly went to sleep. The monitor is the only thing in the loop that
speaks **when nothing has happened**, which is the one event no other mechanism can report.

**Two rules that follow, both absolute — and a third, measured 18.9.2026:**

0. **Keep the machine awake for the lane's whole duration: `nohup caffeinate -i -s -d -t <seconds> &` before the
   first unit, and let the heartbeat report `pgrep -x caffeinate`.** The Mac mini entered *Maintenance Sleep* at
   00:00:41 with an astra fix run in flight and a writer's build queued, and woke at 00:16:27 (`pmset -g log`):
   Codex logged `Reconnecting… 2/5`, both monitors emitted nothing for 30 minutes, and the astra wrapper's wall-clock
   timeout lost sixteen of its sixty minutes. Nothing else in the lane keeps the machine awake (`git grep caffeinate`
   over the project at origin/main and over `~/.claude/scripts` found nothing, 20.9.2026), so the review that runs
   while no build does has no cover without this. Silence from a monitor is the symptom; `pmset -g log | grep -E ' (Sleep|Wake|DarkWake) '`
   is the check.

1. **Start the heartbeat before the first unit**, not when work first looks long enough to warrant it.
   By the time it looks long enough you are already inside the window it exists to cover.
2. **Anything detached gets its own watch in the SAME message that launches it** — a `Monitor`, or a
   background task the harness tracks. If you are about to `nohup`, `disown`, `setsid` or `&` a thing
   and you have not armed a watch for it in that same tool call, do not launch it.

**Reference implementation: `heartbeat.sh` next to this file** — parameterised through the
environment (`HB_SESSION_DIR`, required — the session directory, the parent of `scratchpad/` and
`tasks/`; `HB_REPO`, `HB_WORKTREES` and `HB_STATE_DOC`, whose defaults describe the lane it was
written for and will not match yours), so it is copied and run, not rewritten. Two details in it
look like noise and are not:
the tool name is split so the script's own text cannot trip the `xcodebuild-lock` hook, and
liveness is `pgrep -x` on the exact process NAME.

⚠️ **If you rewrite it anyway, it will self-match on its first tick.** Measured 8.9.2026: a
hand-written gauge counting `ps -Ao args= | grep -c -F '<script>.sh'` reported two live premium runs
while nothing ran, because **the monitor's own command line contains the string it greps for, and so
does the grep**. Splitting the literal into `'sol-''review.sh'` does not fix it either — the string
still appears elsewhere in the same command. What works: gauge **artifacts and locks**, not process
text — branch SHAs read with `for-each-ref`, `.done` files, output sizes, `pgrep -x` on an exact
process name, and the handover document's age. That is the shape that had already worked, in the same
night, for three detached review runs.

### 🔴 5a. A gauge fails by returning a PLAUSIBLE NUMBER, never by looking broken

Three of these in one night, 8.9.2026, all in instruments written to be careful. They are one shape:
**a shell construct that produces a believable value when it has actually failed, matched itself, or
answered a different question.** None of them looked wrong.

| written | what happened | what it read as |
|---|---|---|
| `git status --porcelain \| wc -l` | the repo had been made **bare** by an unrelated incident, so `git status` printed `fatal:` to stderr and nothing to stdout | **`0` = "clean tree"** — and it was reported to the owner as a verified clean tree |
| `ps -Ao args= \| grep -c -F 'sol-review.sh'` | the monitor's own command line contains that string | **`2` = "two premium runs live"** while nothing ran |
| `AR=$(grep -cE 'TERMINAL-(DONE\|FAIL)' log \|\| echo 0)` | `grep -c` prints `0` **and exits 1**, so the `\|\| echo 0` fires too and `AR` becomes `"0\n0"` | `[ "$AR" != "0" ]` is TRUE → **"the archive finished"** while it was still on its first platform |

**Three rules, and they cost nothing:**

1. **Every count carries a control that must be non-zero, in the same command.** a grep for a symbol you
   know exists returning its non-zero count is what proves the grep runs at all; a grep answering 0 for that is broken, not
   informative. This single habit catches all three rows above.
2. **Read the exit code, or print a sentinel.** `git status --porcelain; echo "rc=$?"` distinguishes a
   clean tree from a failed command; `wc -l` cannot.
3. **In a monitor, use boolean tests, not arithmetic on command output** — `if grep -q …`, `if [ -f … ]`.
   `grep -c` in a `$( … || … )` is a trap; so is anything where a failure path can concatenate with a
   success path.

⚠️ The deeper point: **counting a string's occurrences is not counting the thing.** The same night, a
census of a symbol returned 22 and read as "the parameter is still there" when the parameter was gone
and the 22 were a different API, its own tests, and comments. Ask for the property (`grep "func foo("`),
not for the word.

An **unconditional** line every 15 minutes — a silent monitor cannot be told from a dead one. It must
carry: each worktree's branch SHA read with `git for-each-ref` (packed and loose refs alike), whether a build is live,
whether a detached review is still running, tasks touched in the last 20 min, and `weekly_scoped`.

- Detect the build by `pgrep -x` (exact **name**). **Never count processes by command-line text** —
  that matches your own command, four times in one night for me.
- **What to do on a heartbeat:** at least one of these must have changed since the last one — a SHA
  moved, a review finished, a build is live, a task was touched. Two identical heartbeats with no
  agent expected to be thinking means something is stuck: read the last task output, or send the
  implementer a short message asking for its state.
- The monitor must **survive a compact**, and it is the delegator's job to stop it at the end.

⚠️ **Orphaned wait loops are the commonest stuck state, and THREE shapes are immortal:** a
self-referential `until ! pgrep -qf "<tool>"` (its own command line contains `<tool>`), the same
thing wearing a pipeline — `until ! ps -Ao args= | grep <tool> | grep -q <worktree>` — which reads
as a narrowing and is the identical self-match, and `tail -f … | grep -q MARKER` on a file that stops
changing (`grep -q` exits, `tail` never gets SIGPIPE because it has nothing to write). Nine of them,
up to 19.5 h old, in one night; **seven more the next day, after this paragraph existed**; and four
more on 6.9.2026 in the second spelling, written by an implementer whose brief warned it about two
OTHER instrument traps and not this one. Naming the trap does not avoid it — and neither does warning
someone else about its siblings. Carry the working FORM, not the warning:

```bash
# WRONG — never terminates: the loop's own command line contains the string
until ! pgrep -f "sol-review.sh"; do sleep 20; done
# RIGHT — count, and correct for the self-match
until [ "$(ps -Ao args= | grep -c -F '<the full unique command>')" -le 1 ]; do sleep 20; done
```

🔴 **A RESUMED agent runs in the parent session's CURRENT worktree, not the one it was spawned in.**
Measured 6.9.2026: an implementer spawned in one unit's worktree reported at the end that its session
was isolated in a later unit's — the orchestrator had moved on through two units while that
agent could still be resumed. Its bare `git` calls followed the shell's inherited cwd, which happened
to stay in the right tree for the whole working session; **that it landed correctly was luck, not
design**, and the same arrangement can put a `git commit` in another unit's worktree.

Two rules follow. **Do not change worktrees while an agent may still need resuming** — finish the
unit, or accept that a resume is now unsafe. And when a unit ends, **verify its landing by SHA on the
branch you expect** rather than by what the agent reports: `git log --oneline origin/main --grep=` for
the unit's own prefix, counted. That check cost one command and settled it.

Better still: **do not wait at all** — run it as a background task and let its completion notify you.

🔴 **Killing one WAKES the agent that was waiting on it** — and if that is a fable agent it writes a
report and bills the fable window (measured: 85 % → 87 % with no delegation). Sweep when there is
headroom. And **before killing anything, ask whose it is** — the discriminator is the profile path
(`~/.claude` vs `~/.claude-bp`) in its command line, not the shape. Shape alone once left me one
`kill` away from another lane's process.

**That near-miss has now happened twice.** The second time the classifier refused a `kill` by PID and
the refusal was the better outcome: a fresh `ps` then showed three PIDs running the other lane's live
review. So, as a rule rather than a caution:

- **print the candidates WITH their profile path first**, and stop if the two sets are not disjoint;
- **never compose a kill list from a listing taken before the previous step ran** — by then it is a
  claim about a state that has moved;
- prefer `TaskStop` on your own task IDs over `kill` on PIDs. It cannot reach anyone else's.

## 6. Compact discipline

Assume a compact can land at any moment.

- Write the two documents **as you go**, never "at the end".
- Mirror them outside the scratchpad after every meaningful update.
- After a compact, **re-measure volatile state** (branch, SHA, in-flight tasks). The summary is
  derived text; the repo is the measurement.

### 6a. 🔴 Two things do this MECHANICALLY, and they exist because remembering did not

The owner's objection was the right one: *"this has to happen automatically, I cannot sit here
watching for a compact."* Neither piece below depends on anyone noticing anything.

**1. The heartbeat carries a staleness gauge** (`heartbeat.sh`: `STATE_DOC` and the lane's branch
prefixes in the `case` at its staleness loop). Every
tick it compares the mtime of the handover document against the newest mtime among **this lane's**
branch refs, and shouts when a branch moved after the document was last written:

```
· 🔴 STATE-DOC STALE by 137m — a branch of this lane moved after the state doc was last written; WRITE IT NOW (worktree-<unit>)
```

The failure it catches is not "the machine got stuck" — it is **a unit LANDING while the handover
still describes the previous one**, which is what actually happened: three hours and two landed units
behind, caught only because the owner asked. ⚠️ Restrict the prefixes to your own lane; a wide
`worktree-u*` glob also matches the other lane and reports "behind" for work this document is not
supposed to describe — **and a gauge that cries wolf stops being read.** The triggering ref is
printed for that reason: a false alarm has to be attributable.

**2. The PreCompact hook copies the session scratchpad**
(`~/.claude/hooks/precompact-snapshot.sh`), so plan drafts, mutation harnesses, findings files and
research notes survive even if nobody mirrored them. It skips directories named `*logs/` or `*logs-*/`, `*.log` files and files over
1 MB and **says so in the snapshot** — one day's scratchpad was 69 MB, of which ~16 MB was
regenerable build logs, and twenty retained sessions of that is 1.4 GB on a disk that had already
needed clearing.

🔴 **Neither of them can save what was never written to a file.** They close the "I forgot to mirror
it" and "I forgot the doc was stale" holes; the "it only ever existed in the conversation" hole is
still yours, and §6b is the list.

### 6b. How to SEE one coming, when you are the one who must act

The harness reports a remaining-token figure in its own reminders. **Read it as a gauge, not as
scenery**, and treat two things as the trigger to flush:

- **crossing your own threshold** — pick one at the start of the run and write it into
  `LANE-<x>-STATE.md` so the number is not re-decided under pressure;
- **being about to pull something large into context**: an implementer's final report, a review
  output, a big `git show`. Those are what actually consume the remainder, and the moment to flush is
  **before** the call, not after reading it.

⚠️ The usual failure is not running out — it is running out **holding the only copy of a
measurement**. A number you have run but not written down is the thing a compact takes.

### 6c. What the PreCompact hook does and does not carry

`~/.claude/hooks/precompact-snapshot.sh` is wired in `settings.json` and writes, per session: the
time, the trigger, cwd, branch, `HEAD`, `git status --short`, the stash count — **and since 7.9.2026 (commit 83eceee, measured 6.9.)
a copy of the session scratchpad** (§6a). After a compact it is the thing to trust over the summary.

**It still carries nothing that existed only in the conversation:** not the acceptance numbers
already obtained, not which findings were accepted or rejected and why, not the open decisions, not
what the in-flight unit was about to do. So it is necessary and not sufficient, and the flush is
still yours:

| into `LANE-<x>-STATE.md`, before the compact | why the hook cannot |
|---|---|
| the in-flight unit's SHA **and what it is** | the hook has the SHA, not the intent |
| every acceptance number already run | re-running them costs the time again |
| findings accepted / rejected, with the reason | a rejection with no reason gets re-litigated |
| the open decisions and the default you took | otherwise the next session re-decides differently |
| what is running in the background right now | a task notification after a compact names an ID that means nothing |

## 7. Anti-patterns

- Writing the implementation yourself, in either version.
- Taking any number from the agent's report into the Status without re-running it.
- A third review round without the operator's word.
- Presenting a settled decision as a new finding (grep symbols first).
- Reporting a surviving mutation as a hole without tracing its reader.
- Reading `UP-TO-DATE` as coverage.
- `git ls-remote` skipped because `git push` printed no error.
- Faking `discard_changes: true` when a tool asked for the user's confirmation and the user is
  asleep. The worktree costs nothing once its DerivedData is gone.
- A "fix" for a worker/server that ends in a commit but is described as if deployed. Say
  **commit only**, and say when it starts to matter.
- Asking the operator questions one at a time as they arise.
- Scoring a mutation matrix on exit codes, so a flaky baseline or a VOID sub-harness reads as
  "caught".
- Prescribing a check in the plan without naming the input that defeats a naive version of it.
- Reporting a peer's finding onward without reproducing it — **and** reporting your own correction of
  it without reproducing that either. A peer is a reviewer; the rule does not change.
- Reading only the first clause of a triage row. Three times in one series the parenthesis carried
  defects worse than the sentence
- Letting a plan GROW on measurement without checking whether it should shrink. Three units in one
  series got smaller once measured: a tri-state whose case could not occur, a snapshot marker whose
  case could not occur, and a ratio harness that two redundant assertions made unnecessary.
