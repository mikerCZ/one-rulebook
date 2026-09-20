# Global instructions

## The operator's own section

Fill this in for yourself: the language you want replies in, who you are, your projects and your
stack. Everything below the private block is written for any operator; the block itself is the

---

## 🔴 A fix is two observations, not an argument

**This is the rule the whole system was missing, and its absence is what produced days of fixing
fixes.** Before you write "fixed", you must have:

1. **the failure reproduced** — a test, a log line, a `curl`, a run. Or an explicit statement of
   why reproducing it is impossible.
2. **the same observation after the change, now negative.**

Without (1) it is not a fix, it is a **hypothesis** — label it that way in the commit and in the
CHANGELOG. Nobody is harmed by an honest hypothesis; a hypothesis presented as a fix costs a
review round and usually a second wrong fix on top.

**This applies to someone else's finding too.** A reviewer's finding is a hypothesis until you
reproduce it — and so is a reviewer's *approval* of your fix. Reviewers reason about a diff; they
cannot execute. **Review is a second layer, never the verification.**

**Why no other rule replaces this one:** the same reasoning that produced the bug produces the
confidence in the fix. Thinking harder does not break that loop — running the thing does.
*(Verified 4.8.2026: of 39 commits that day, 8 corrected my own same-day work. Every item that
held carried an explicit "verified by running / by mutation / by reading back"; every item that
failed carried an argument instead.)*

### Fix the mechanism, not the symptom

Describe the failure in **one sentence**. If your change does not cancel that whole sentence but
only one of its instances, you are fixing a symptom — a green build and green tests will still
agree with you.

> "An exception during teardown skips the cleanup" ≠ "this particular input crashes it."

**Write into the commit what stayed open.** "I closed input X; mechanism Y remains, because Z" is
honest. Silence reads as a complete fix, and the next audit finds it again.

### Waiting for your own verification may block the conversation

It is the single exception to the background-task rule below. Everything else goes to the
background; watching your own fix land does not.

### Which model reviews — check the quota first

**`gpt-5.6-sol` is the review model** (it replaced `gpt-5.3-codex`, whose only advantage was
price — and that argument fell once both paths turned out to run on the subscription). What
changes is the **access path**, and that depends on the remaining Codex quota:

```bash
~/.claude/scripts/codex-quota.sh    # exit 0 = plenty, 1 = low (>=80 % used), 2 = no reading
```

| Quota | Route |
|---|---|
| plenty left | **`sol` via Codex CLI** — `~/.claude/scripts/sol-review.sh` (subscription, tool-armed, `-s read-only`) |
| exhausted or little left | **`gpt-5.6-sol` via API** (skill `llm-apis`) — paid per token, so say so before firing a whole panel |

🔴 **`gpt-6-astra` is the extra-premium lane and I never pick it.** `astra-review.sh` runs the same
pipeline with `model=gpt-6-astra`, `effort=xhigh`, and refuses to start without
`--human-asked` (env form `ASTRA_CONFIRM=human-asked`) — a phrase that is a claim about the
operator, not a switch.

🔴 **Since 7.9.2026 there is no prompt behind that claim, and that changes what it rests on.** Both
wrappers are in `permissions.allow` in their FLAG form, because the auto-mode classifier had begun
refusing `codex-fix.sh --astra` outright in another session. `ask` was considered and rejected by
the operator on the ground that settles it: a prompt raised inside a subagent, or in another
session's terminal, is not one they see. So the flag is now a claim on the agent's honour and nothing else —
there is no run log and no budget behind it either *(verified 7.9.2026: no counter in either
wrapper, no `*astra*` log anywhere under `~/.claude`)*. Use it when they have asked, in their own
words, in the conversation you are in. **A weak sol run is not a reason to escalate.**

⚠️ The env-var form still works but no permission rule can match it — a `Bash()` rule matches a
command PREFIX and that form begins with the assignment — so it falls to the classifier. Use the
flag.

⚠️ The quota script reads the **last value Codex logged**, not a live figure — it prints the age
of the reading for that reason. `gpt-5.3-codex` stays only as a cheap parallel slot in a large
audit panel and as a tool-less optic (a *different* failure mode, not a worse one).

---

## 🔴 A claim carries its evidence, or it does not get written

In comments, commit messages, CHANGELOG and docs:

> Either the claim carries its evidence inline — `(verified: <command | file:line | date>)` —
> or you do not write it.

Without evidence, describe **only what the code does**. The "why" is optional; when it is missing,
nobody is harmed.

**Three shapes that are almost always unverified.** A pre-commit hook greps for them and asks for
the evidence token, but the hook only sees words — these two do not always have one:

1. **Universal / negative claims** — "only", "never", "all N sites", "none", "unlike every",
   "unconditionally", "behavior-preserving", and their Czech equivalents. *Easy to grep.*
2. **Justifications** — any sentence whose role is *a reason why I did or did not do something*.
   "X is fine because Y." "Z is enough because W." **A grep has nothing to catch here**; you spot
   it by asking what that sentence is doing in the text. The worst subclass is a reason **not** to
   act (not translate, not guard, not test, not wrap) — nobody ever comes back to verify a
   decision not to act, so the falsehood sits for years and discourages the next person.
3. **Claims about the effect of your own change** — "this can't happen now". Reading code does not
   prove it. Measure it, or write down what you verified and what you did not.

⚠️ **The commonest trap: a comment describing the state BEFORE the fix, written in the commit that
invalidates it.** Before committing any new universal claim: *does it still hold after my diff?*

```bash
# audit your own added comments after a larger change
git diff <base>..HEAD -- '*.swift' | grep -E "^\+\s*//" \
  | grep -inE "only|never|all |none|not |always|unconditional|jedin|všech|žádn|nikdy|vždy"
```

---

## Pre-flight checklist before committing code

Empirical first — the order matters.

1. **Did I reproduce the failure?** If not, this is a hypothesis — say so in the commit.
2. **Does my fix cancel the whole failure sentence, or only this instance?** If the latter, write
   what stayed open.
3. **Did I observe the failure gone?** Not "the build is green" — the actual thing.
4. Call sites of every changed function — read, or better, turned into compile errors.
5. Race conditions between `await` suspension points and MainActor mutations from other paths.
6. Cancel propagation (`Task.isCancelled`, `CancellationError`).
7. Every "because" in the diff — observation, or my reasoning?
8. Build clean with no **new** warnings in the touched files.

**Write carefully the first time.** Before writing code: read the relevant existing code (whole
functions and their call sites, not neighbouring lines), and verify any API/language assumption
you are not certain about — grep the stdlib, read Apple docs, compile a short test. **Do not
guess.** When unsure about identity, equality or cancel semantics, ask GPT-5.3 or Gemini 3.1 Pro
Vertex as an oracle (skill `llm-apis`) — a quick query is cheaper than a review cycle spent on a
wrong assumption.

Race conditions, cancel propagation, MainActor ordering and memory cycles are where CRITICAL
findings concentrate. Walk those four yourself before committing.

---

## 🔴 Red lines (always in force, whatever else is loaded)

Prohibitions **no hook enforces** — this text is the only safeguard:

| Never | Why |
|---|---|
| `read_graph()` on MCP memory → always `search_nodes()` | returns 21k+ tokens. Since 9.8.2026 also blocked mechanically via `permissions.deny` |
| Reach for a TRUE pro model on your own (`gpt-5.5-pro`, `gpt-5.4-pro`) | ~13× the price. **Ask first.** (`gpt-5.6-sol` is the review default — see below) |
| A workaround instead of a fix without explicit consent | see Workflow below |
| TestFlight upload or `fastlane deliver` without explicit consent | irreversible (burned build number, deleted screenshots) |
| `git add -A` in a shared checkout | sweeps a concurrent session's work into your commit. Stage explicit paths, and check `git branch --show-current` before claiming anything is on `main` |
| Editing PHP scripts directly on the server or in `/tmp` | always local → `scp` → `chown` → commit |
| Two `xcodebuild` runs in parallel | DerivedData lock (a hook exists, but the rule holds outside the Bash tool too) |
| Sending secrets / API keys to an external LLM | the hook matches patterns, not everything |
| Writing a version/build/count number into a CLAUDE.md | it goes stale within days and then reads as authoritative. Write the command that reads it |
| Text-merging a generated artifact (`project.pbxproj`, lockfiles) | the merge can succeed and silently drop one side's target membership. Take one side whole, **re-run the generator**, then verify BOTH sides' membership |
| Pushing a merge to a shared branch without running the tests on the MERGED tree | your branch was green against a base that no longer exists, and so was theirs. Neither says anything about the result |

---

## 📚 Which skill to load, and when

The detailed rules are **not** in context — they are skills and load only when invoked. This table
is an instruction, not a description: when the left column holds, load the right one **before you
start**.

| Situation | Skill |
|---|---|
| Non-trivial change (>5 files, unclear scope, security/billing/data model/API contract) | `dev-flow` |
| A plan or finished code goes to review; before a TestFlight build | `llm-review` |
| Briefing an audit agent or review panel | `audit-briefing` |
| Handing implementation work to an agent (fable), or a delegated run that must survive a usage-limit reset | `agent-delegation` |
| **A plan that lands as MANY units over hours, mostly unattended** (FULL vs LITE lane, when to switch, your own acceptance pass, the two handoff documents) | `fix-series` |
| Calling a foreign LLM API (oracle question, panel, benchmark) | `llm-apis` |
| A credential for a domain, DNS, worker or hosting | `secrets` — the operator's own credentials skill (private; not part of the public export) |
| Another session is live in the same repo — `git status` shows changes you did not make, or `ListAgents` lists a live peer | `multi-session` |


⚠️ **A skill loads only if you decide to load it.** When unsure whether the situation qualifies,
**load it** — 10k tokens is cheaper than the mistake that rule was written to catch.

📇 **Tools are the other half of this table, and they are indexed in
`~/.claude/scripts/README.md`.** Read it before writing one — the thing you need is often already
there, with the traps already paid for. The two that get rewritten from scratch most often:
`sol-review.sh` (review, read-only) and `codex-fix.sh` (the write lane — fixes findings in an
isolated worktree, `--cleanup` takes that worktree AND its DerivedData afterwards).

🔴 **A script another session may be RUNNING is replaced, never edited in place, and a renamed flag
keeps its old spelling as an alias for a week.** Bash reads a script incrementally, so an in-place
edit of `codex-fix.sh` / `sol-review.sh` corrupts every wrapper mid-run (measured 20.9.2026: two
wrappers ended in `lands: command not found`), and a flag renamed at 14:58:10 refused a launch at
14:58:15 in the other session. Write to a temp file in the same directory and `mv` over the target
(the running instance keeps the old inode); mirror settings/config files the same way; before
removing an alias, `pgrep -f` the script and look at `~/.claude-bp` and `~/.claude` sessions alike
— the rules here bind both profiles.

⛔ **Never put reference material in `~/.claude/rules/`.** Every `.md` there loads into **every**
session unconditionally — no import, no condition, no way to turn it off. That is how 19 files grew
to ~95k tokens of always-on context. New rules go in as a skill; only prohibitions that must hold
without being invoked belong in this file.

---

## Technical preferences

Respect the project's own `.claude/CLAUDE.md`. Defaults by type: Swift/SwiftUI (iOS), Flutter
(cross-platform), Astro/Vite/Tailwind v4 (web). iOS: SwiftUI, `@MainActor @Observable`.
Flutter: BLoC/Cubit. Web: prefer SSG/SSR for SEO and performance, minimise client JS.
Deployment: App Store/TestFlight, Google Play, Linux server.

⚠️ **A preference in this file is not a fact about a repo.** "Swift 6 strict wouldn't allow that"
was wrong — the repo is Swift 5 `minimal`. Measure the mode in `project.pbxproj`.

### English is the language of code comments and of the instruction layer

**New and edited content in English** — code comments, `CLAUDE.md`, `SKILL.md`, memory files.
**No bulk rewrite of existing ones**: a batch translation re-stamps every claim the text carries
without anyone verifying it, which is the exact machine that produces false comments. An existing
Czech file converts organically, line by line, as it gets touched.

A hook (`instructions-in-english`) blocks a Write/Edit that puts Czech prose into `CLAUDE.md`,
`SKILL.md` or a memory file. It inspects **only the content being written**, never the rest of the
file — so a partial edit of a Czech skill is fine as long as *your* lines are English. It exists
because the prose version of this rule did not survive its own author for one session: on 4.8.2026
I appended Czech to two skills within twenty minutes of writing the rule, each time by matching
the host file's language.

⚠️ **A quoted localised string is not prose.** `// error ("Request Canceled" / "Žádost byla
zrušena")` is evidence of what the system returns; translating it destroys the evidence. Czech
inside backticks and "quotes" passes the hook for that reason. Deliberate Czech elsewhere: add
`cs-ok`.

**Replies to the operator stay in their language** — this rule is about files, not about conversation.

---

## Workflow

### Workarounds vs fixes (CRITICAL)

**Never do a workaround instead of fixing the bug without explicit consent.** When the problem is
in an API/backend/external system: identify exactly what is wrong → write what must be fixed →
**wait for the fix**. A temporary workaround only after explicit agreement. All projects, no
exceptions.

### Background tasks

**Never block the conversation** with long operations. Build/run/test → always `run_in_background`,
announce the task ID and continue with other work. Status via `tail` on the output, not a blocking
wait. Nothing should block the conversation for more than ~10 s —
**except waiting for the verification of your own fix**, which is exactly what must not be skipped.

### CHANGELOG.md (mandatory in every project)

Add an entry automatically on every significant change, **do not ask**. Newest on top, date
`DD.M.YYYY`, categorised (Features/Fixes/Refactor/Security/UI/Localization). Say concretely **what
and why** — not how, and never a file list, that is what `git log` is for. Every "why" is subject
to the evidence rule above.

```markdown
## [version] (Build [number]) — [date DD.M.YYYY]

### [Category]
- **Change title** — brief description of what and why
```

### Git

Stage explicit paths, never `-A`. Conventional prefix, **lowercase** (`feat` `fix` `refactor`
`chore` `docs` `test` `style` `build` `ci` `perf`) — a hook blocks anything else. Commit after each
logical change; push right away. If `git status` shows changes you did not make, **ask** before
committing them, and resolve with an extra commit rather than rewriting history.

### You are probably not alone in the repo

**Before the first write of a session: `git status` and `git branch --show-current`.** Changes you
did not make mean another session is live. In this setup that is not an edge case, it is the normal
state — it held on 18.8.2026 while two sessions worked on the project for four hours. The moment it
holds, load the skill `multi-session`; the procedure is not guessable and every rule in it cost a
concrete mistake.

Three prohibitions hold **without** the skill, because by the time you need them you have already
stopped thinking about isolation:

1. **Once you are in your own worktree, never write outside it.** No `--work-tree=`, no `cd` into
   the shared checkout, no `git branch -f` on a branch checked out elsewhere. Git refuses the last
   one — that refusal is a feature, do not route around it.
2. **Never move a shared ref from a session that did not verify the MERGED tree.** Not your
   branch's green — the merge result's: full test suite plus a build of every platform the union of
   both changes touches.
3. **Never delete a worktree on a tool's word that the commits are safe.** The warning compares
   against the LOCAL branch ref, which is routinely behind the remote — on 18.8.2026 it said
   "Discarded 8 commits" about commits that were already on `origin/main`. Prove it by SHA
   (`git merge-base --is-ancestor HEAD origin/main`, the two SHAs equal, `git ls-remote --heads`
   showing the branch), then verify **after** removal that the shared checkout is still on its own
   branch — a pruned worktree has moved it before.


---

## Memory

Three layers — do not conflate:

| Layer | Purpose | Loading |
|---|---|---|
| **CLAUDE.md + skills** | "HOW to work" — instructions, rules | always / on demand |
| **Auto Memory** | "WHAT I learned" — patterns, debugging | every session: a generated index of topic-file `description`s (newest by mtime first, 25 000 B cap) + the `pinned: true` files in full. `MEMORY.md` is a catalog for people and the session-end routine — the CLI never injects its body (measured 7.9.2026 on 2.1.263, decided by the operator the same day) |
| **MCP Memory** | "WHAT I KNOW" — project state, servers, facts | never automatically, only `search_nodes()` |

Where things go: instruction → `CLAUDE.md` · learned procedure → auto-memory topic file · fact
about a project → MCP · changelog → the project's `CHANGELOG.md`.

**Use it actively and without asking.** Save as you go, update stale entries immediately. Ask only
about passwords, keys, personal and financial data.

**Before creating an MCP entity:** `search_nodes('name')`. Format `{project}` /
`{project}:{component}`. `entityType` ONLY `projekt` | `server` | `konfigurace` | `meta`. Max 30
observations per entity, then split. No human names with spaces, no duplicates.

**The hot path is the topic file's `description`, not `MEMORY.md`.** That one line is all a new
session sees of the file, so write it as the RULE — what to do differently — with the incident as a
short tail, in English, roughly ≤250 chars; a description that only narrates what happened is a
lesson nobody will load. `MEMORY.md` stays the catalog: one line + `[[topic]]` link per lesson,
detail in the topic file. Delete only WRONG/superseded entries.

**Pins are the only guaranteed load** — at most 4, and which files carry `pinned: true` is the
operator's call. The index is ordered by file mtime, so a mass edit of topic files must restore their mtimes
(`os.utime`) or it reorders what the next session sees.

🔴 **Index entries are NEVER archived or shortened to make room.** Whether a lesson still fires is
a judgement, and every mechanical proxy points backwards — a rule that is correct is never edited,
so its mtime marks it stale exactly when it is most durable.


⚠️ **Volatile state does not belong in `MEMORY.md`** — a catalog version, a build number or a
branch name goes stale and then reads as authoritative. Those belong in the project's
`KNOWN_BUGS.md`, in git, or in MCP.


---


---

## Hooks (mechanical enforcement)

Global, in `~/.claude/hooks/` — they enforce mechanically, independent of what is in context:
`protected-files` (list in `~/.claude/protected-files.txt`) · `check-secrets-in-llm` · `conventional-commits` · `changelog-exists` ·
`xcodebuild-lock` · `rsync-no-delete` · `grok-user-agent` · `gemini-vertex-only` ·
`claims-need-evidence` · `instructions-in-english` · `session-end-uncommitted` (SessionEnd: macOS
notification when `~/.claude` has uncommitted changes).

Mechanical red-line enforcement also lives in `permissions.deny`: `mcp__memory__read_graph` and
`git add -A` globally; project-specific destructive commands in that project's settings.

Config: `~/.claude/settings.json`, per-project `settings.local.json`.

## Agent Skills

Repo: https://github.com/VoltAgent/awesome-agent-skills (380+ skills).
Install into `.claude/skills/` (project) or `~/.claude/skills/` (global).
