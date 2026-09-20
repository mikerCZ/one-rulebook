---
name: audit-briefing
description: "How to brief audits and code review agents — ban on reading rationale docs, NET diff at HEAD, distinct lenses (correctness / race / money / hostile), permission to find nothing, accept findings per-claim not per-reviewer. Load BEFORE launching any audit agent or LLM review panel."
---

# How to brief audits and code reviews

Complements `skills/llm-review/SKILL.md` (who, which models) and `skills/dev-flow/SKILL.md` (when, Phases 3/5). This file is
about the **brief**. Most worthless reviews are worthless not because of the model but because of the prompt.

Every rule below cost one concrete mistake (10.7.2026: a 6-LLM panel + 2× Sonnet
approved a fix that introduced a new regression; only a clean Opus audit banned from reading the plan caught it).

---

## 1. A reviewer who knows your reasoning does not verify it — it rationalises it

**In the brief, explicitly FORBID reading:**

```
⛔ DO NOT READ — they contain the author's reasoning and will make you agree:
   docs/<FEATURE>_FIX_PLAN.md, docs/KNOWN_BUGS.md, docs/AUDIT_BACKLOG.md, CHANGELOG.md
Read commit messages only for WHAT changed, never for whether it was right.
Every docstring and comment in the diff = the author's UNVERIFIED claim. Verify it against the code.
Never cite it as evidence.
```

Without that, the reviewer reads "reverted after tracing the readers" and writes "confirmed correct".
The Phase-3/5 panel has the plan available deliberately (it judges intent). **A clean audit must not have it.**

## 1b. That ban MOVES deduplication onto you — do it before you report a finding

A reviewer denied `KNOWN_BUGS` / `AUDIT_BACKLOG` / `CHANGELOG` **cannot know what has already been
assessed and deferred**. Every deferred finding is new to it. That is not its fault — it is the price
of rule #1, and you pay it.

**Before you present any finding as new, search `KNOWN_BUGS.md`, `AUDIT_BACKLOG.md`
(including "Won't fix / decision log") and `CHANGELOG.md`** for the symptom, the symbol and the ticket. Then put it
into one of three boxes — and **say the box out loud**:

| Category | What to do with it |
|---|---|
| **New** | normal processing |
| **Known and deferred** | report it as *"this already came up in X, the conclusion was Y"* — and decide whether anything has changed. Do not present it as a fresh finding. |
| **Known, but with NEW evidence** | the most valuable case. Old conclusion + new measurement = a reason to confirm or revisit it. |

That third category is why a duplicate finding must not simply be discarded: a re-found item can carry a
measurement the original assessment never had, and that either confirms the old conclusion or reopens it —
while presenting it as new gets both the severity and the novelty wrong and sends the work in the wrong direction.


**When it turns out to be a duplicate, write it into `AUDIT_BACKLOG` with a link to the original ticket** —
otherwise it surfaces a third time. The backlog is the only place where you can keep this memory, because the agents
must not see into it.

## 2. Brief the NET diff at HEAD, not a range of commits

Commits inside the range revert each other. An agent that reads `git log` reports as a defect
something that is fixed three commits later.

```
SCOPE — the NET diff at HEAD, not the intermediate commits:
    git diff <BASELINE> HEAD -- '*.swift'
Commits inside that range revise each other. Judge only the final state; read files at HEAD.
```

⚠️ `HEAD` moves under the agent if you commit in the meantime. Either do not commit, or give it a concrete SHA.

## 3. Different LENSES, not more reviewers

Six tool-less LLMs on the same closed question = six correlated answers, not six views.
The consensus of such a panel **is not evidence**.

Proven lenses (one per agent, never mix):

| Lens | Question |
|--------|--------|
| **Correctness** | Does the code do what its names, signatures and comments promise? |
| **Race / crash** | Await-suspension atomicity, TOCTOU across an actor hop, cancel propagation, reentrance |
| **Money / sync** | Can a paying user lose what they bought? Can a non-paying user gain something? Can two devices diverge? |
| **Hostile** | "Break it in the direction that costs money." Construct attacks, not remarks. |

In practice the hostile framing has been the one lens that produced a new finding the other three missed.


## 4. Without tools = hallucination, with tools = also, just less

A tool-less LLM makes up file paths and line numbers. **And Opus with tools does too** — today it cited
`<a lint script>:504-509` in a file of 121 lines, even though the description of the logic was right.

- **Accept per claim, not per reviewer.** One reviewer had, in a single answer, both a correct finding
  and an invented `else` branch.
- **Raise severity only** when at least one verified it with grep.
- At least one reviewer in the panel MUST have tools (Sonnet Plan agent / Opus Plan agent).

## 5. Make them refute themselves

```
Before reporting a finding, try to REFUTE it. Write down what you tried and why it survived.
Cite every claim with a file + symbol you personally opened (section 10: symbols, not line numbers). No speculation about unread code.
Distinguish "pre-existing" from "introduced today" via `git show <BASELINE>:<file>`.
A pre-existing problem reported as today's regression = a false positive and counts against you.
```

Without the last two sentences the report swells with pre-existing things and looks productive.

## 6. Give them permission to find nothing

```
Do not invent findings. "I attacked X, Y, Z; this is what stopped each of them" is a valuable answer.
```

Without that, the reviewer manufactures a MEDIUM so as not to look useless.

---

## 6b. Do not hand the reviewer facts and then have it verify claims that repeat those facts

Into a Phase-5 brief I put a section "GROUND TRUTH — verified by grep, do not re-derive" (correctly, so that
the tool-less model would not hallucinate) and in the same message asked it to check my comments in the code.
But those comments claim **the same thing as the ground truth**. Codex returned "prose is clean" with the justification
*"verified by given ground truth (#2)"* — i.e. it verified that my comments agree with my facts.
**A tautology, not verification.** And it looks green.

- Give ground truth **only** for what the reviewer is NOT supposed to verify.
- A claim you want verified **must not be in the ground truth** — not even paraphrased.
- Verifying a claim about code **outside the diff** can only be done by a reviewer with grep. A tool-less model
  answers them from what you dictated to it.

## 6c. A correctness fix can introduce a performance regression. Ask "how many times per second?"


So the brief must explicitly contain: *"for every new call in `body`/a computed property: what does it cost
and how many times per second is it called? What invalidates it?"* — otherwise the reviewer only asks "does it return
the right value?".

## 7. Verify a reviewer's APPROVAL as strictly as its finding

Gemini declared the code "perfectly safe and correct" with a justification that **it had itself contradicted
two paragraphs earlier**. Approval is not verification.

## 8. Verify a reviewer-proposed FIX MORE STRICTLY than its finding

A finding is a hypothesis. A fix is a change. Before accepting it, trace **all** readers of the affected state.

A fix that mirrors a neighbouring line for symmetry can buy only performance and pay for it with the one
clause that kept a behaviour alive — the neighbour had a correctness reason, the mirror did not, and that is
exactly the trap symmetry sets.


## 9. A green test/lint proves nothing until you see it fail

And verify it against the **space of mutations**, not against the one you expected.

A lint "verified by mutation" was bypassed by two rewrites of the guarded call: one where the whitelist matched
as a substring of a longer expression, one where the call spanned two lines and the scanner was line-wise.


For every guard also write a **control** mutation that must not fail anything, and **name in a comment
what the guard does not see** (another file, a computed property, an `inout` alias).

## 9b. Run a mutation matrix ONLY over a committed baseline — and distinguish a build failure from "passed"

A harness that does `git checkout -- <dir>` after every mutation **reverts your own uncommitted
work too**.

- **Commit BEFORE the matrix.** Then `git checkout` restores HEAD, which is your work, not nothing.
- **A build failure must be a third state**, not an empty result. `if grep -q 'error:' → "BUILD FAILED"`,
  otherwise you count a mutation that does not compile as "the test did not catch it".
- `checkout` **does not restore** an untracked file — a mutation in a new file stays there after the "revert".
- Better still: mutate an **isolated copy** of the tree, not the repo. A clean Opus did it that way on 19.7. and
  did not touch the repo at all.

## 9c. "A guard in the right place" ≠ "a guard that does something"

Three different ways a lint passed today on a guard that did not work:

1. **`+x` was missing.** The hook has `[ -x script.py ]`; a file created by writing has 644 → the block is **silently
   skipped**, reports nothing. The check "`grep -c` returns 2" proves the text IS in the hook, not that it
   **runs**. → **Actually run the hook** over a staged file.
2. **The rule guarded the position, not the effect.** A gate left in the right place, just without `return nil`:
   analytics reports the action, control falls through. Lint green.
3. **`#if DEBUG` around `return nil`.** Passes the lint **and `swift test`** (SPM builds debug) and
   only the shipped Release is broken.

→ For every guard ask **"what happens if I leave it looking the same and gut its effect?"**
And verify the **negative** state too: a guard is unproven until you have seen it catch a violating mutation and let a non-violating control through.

## 10. Cite symbols, not line numbers

A citation `file:1915` rots as soon as you insert code above it — often in the same session, by your own
edit. Today 2× in one day. Write "at the end of `loadPurchases`", not "`:1010`".

## 11. Audit again after a fix — and have the FIXES THEMSELVES audited too

A fix is new, unaudited code. A fix for a race has introduced a new race in the same session.
Let the re-audit judge the **resulting state**, and tell it what the previous audits found so it does not report them again:

```
Previous audits found A, B, C. All of it is claimed to be fixed at HEAD.
Do NOT report them again unless they are still there — verify.
Your value is in what they missed, AND IN WHAT THE FIXES THEMSELVES INTRODUCED:
new prose, new regexes, new comments, new guards.
```

That last sentence is the one that goes missing, and it is expensive: a briefing that says "this is
claimed fixed, verify" sends the auditor to re-test old defects, not to audit what the fixes themselves
introduced.

## 12. Do not give the auditor a list of files. Give it the diff.

In my brief I listed `<a lint script>` as part of today's work. It has a zero diff
(unchanged since May). An auditor that trusts the list more than `--stat` starts auditing pre-existing
code and its findings are false positives. Write "`git diff <BASE> HEAD`, start with `--stat`" and let it
establish the scope itself.

---

## Operational notes

- **An agent transcript is flushed only at the end.** A 133 B file ≠ a dead agent. Today I twice
  declared a running Sonnet dead this way and needlessly launched a duplicate.
- **MiniMax M3 (OpenRouter)** returned HTTP 200 2×, finish reason `stop`, empty `content`
  (at 16k and 40k `max_tokens`). The panel ran 6/7 — above the minimum of 2, so OK.
- **GLM-5.2** with thinking: `max_tokens` 32768 is not enough for a large review, `content` comes out empty
  and `reasoning_tokens` swallows everything. Set 65536 and also print `reasoning_content` when `content` is empty
  (measured 20.9.2026 on a 17K-token review prompt: 32768 → all 32768 tokens went to reasoning, finish reason `length`, empty `content`, 450 s; 65536 → finish reason `stop` at 40822 completion tokens (37123 reasoning), 538 s).
- When: before TF, after every T2/T3 fix, **and again after fixing the findings**.
