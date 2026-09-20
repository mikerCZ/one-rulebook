---
name: llm-review
description: "LLM code review — model panel, procedure, severity calibration, re-review loop. Load BEFORE reviewing a plan (Phase 3) or finished code (Phase 5), before any TestFlight build, and whenever the user says /review or asks for an LLM review."
---

# LLM Code Review — rules and procedure

> Pruned and translated 4.8.2026. Rules live here; the dated measurements they were derived from
> moved to [HISTORY.md](HISTORY.md) (verbatim until 20.9.2026, translated to English since). When you want to question a rule, read the evidence
> there — do not re-derive it.

## When to use

- Before a TestFlight build (pre-flight)
- After a larger implementation (new feature, refactor)
- On request (`/review`, "review od llms")
- When working a feedback ticket (root cause analysis)

---

## 🔴 Which model, and which route

**The review model is `gpt-5.6-sol`, for both phase 3 and phase 5.** It replaced `gpt-5.3-codex`,
whose only advantage was price — and that argument fell once it turned out sol over Codex runs on
the **subscription**, not on API billing.

**What gets decided is the ROUTE, not the model.** Measure the remaining quota first:

```bash
~/.claude/scripts/codex-quota.sh   # exit 0 = plenty, 1 = low (>=80 % used), 2 = no reading
```

| Quota | Route |
|---|---|
| plenty left | **sol over the Codex CLI** — `~/.claude/scripts/sol-review.sh {plan\|review} <repo> <brief> [out]` (subscription, tool-armed, `-s read-only`) |
| exhausted / low | **`gpt-5.6-sol` over the API** (skill `llm-apis`), ~$0.26–0.35/review (list price at 3K in / 8K–11K out — derivation in HISTORY.md) — say so up front before a whole panel |

⚠️ The script reads **the last value Codex logged**, not a live figure — that is why it also prints
the age of the reading. An old reading is a weak basis for a routing decision.

- **True pro `gpt-5.5-pro` / `gpt-5.4-pro` (~13×) only when the user explicitly asks.**
- **`gpt-5.3-codex` survives** in three specific roles, none of them "default":
  1. **Fallback when the Codex quota is spent.** The subscription has a ceiling; the API does not.
  2. **Cheap parallel slot in an audit panel.** The Codex CLI is one process; an audit runs six
     reviewers at once and the API scales without that limit.
  3. **Tool-less optic as a DIFFERENT failure mode, not a worse one.** A reviewer without tools
     cannot be misled by a bad grep. `audit-briefing` #3: a panel's value comes from differing
     failure modes, not from head count.

⏳ Watch for deprecation — `gpt-5.3-codex` is the last surviving codex model.

---

## 🔧 MANDATORY in every brief: the reviewer supplies a FINISHED PATCH

**For every finding, ask for the exact replacement code, not a description of an approach — then
apply it verbatim.** Applies to every slot below (`sol`, `agy`, `fable`, the panel, Claude agents),
to the API and to the wrappers. The wrappers inject it themselves via
`~/.claude/scripts/review-guard.md`; **when calling the API or the Agent tool directly you must
write it into the prompt yourself** — the guard does not apply there.

Wording that worked:

> For every finding, give me the concrete patch you want applied — exact replacement code, not a
> description of an approach. I will apply what you write. That means it has to be complete and
> compile-ready, and if you are not confident enough to write the code, say so and explain what you
> would need to check first, rather than guessing.

**Why (five rounds on one build, 28.7.2026 — data, not impression):**

| Round | Who wrote the fixes | Result |
|---|---|---|
| 1–3 | me | **every round introduced a new defect** that only the next round found |
| 4 | the reviewers | 2 findings, **the first round with nothing wrong in the previous round's code** |
| 5 | the reviewers | clean from both sides |

It is not about smarter code — those patches were trivial. It is about **changing my role**: from
"invent the right fix" to "verify this patch fits the actual code". The second question has a
factual answer (does that symbol exist? is that type `Equatable`? does that branch reach that
line?) and I get those wrong far less often. Detail in [HISTORY.md](HISTORY.md).

⚠️ **Checking applicability is NOT invention and must not be skipped.** In round 4 two of five
findings were factually off-target and one patch would have produced a **false message to the
user**. All of it was greppable. **Accept per-claim, not per-reviewer.**

⚠️ **When a reviewer admits uncertainty, that is a signal, not a weakness.** Both wrong findings
came with "I cannot see the whole function" — the fault was in my package, not in the reviewer.
For a tool-less slot, always include **whole affected functions**, not just diff hunks.

---

## ⭐ Default for reviewing MY OWN work: `sol` + `agy`

**Applies to phase 3 (plan review) and phase 5 (finished code)** — where what is judged is what I
wrote. **Does not apply to audits of existing or foreign code** — see the distinction below; it is
the most important sentence in this section.

| Slot | How to run | Role |
|---|---|---|
| **`gpt-5.6-sol`** | `~/.claude/scripts/sol-review.sh {plan\|review} <repo> <brief> [out]` | **Primary.** Tool-armed, `-s read-only` hard-wired. |
| **`agy` (Gemini 3.8 Flash High by default, `AGY_MODEL` overrides — measured 4.9.2026 in `agy-review.sh`)** | `~/.claude/scripts/agy-review.sh survey <repo> <brief> [out]` | **Corroboration, not verification.** Different training family, on the subscription. |
| **`fable`** | Agent tool, `model: fable`, `subagent_type: general-purpose`, brief in the prompt | Tool-armed: probes live APIs, runs mutation matrices and reports which mutations survived, finds call sites outside the diff. Honest about what it could not reach. |
| **`gpt-6-astra`** | `~/.claude/scripts/astra-review.sh --human-asked {plan\|review\|verify} <repo> <brief> [out]` — the FLAG form, since 7.9.2026 the one form a permission rule can match | 🔴 **Premium lane — solely when the operator asks for astra in their own words.** Thin wrapper over `sol-review.sh` (same guard, same read-only sandbox), model `gpt-6-astra`, effort `xhigh`. |

### The fix lane is a SECOND run, never a flag on the reviewer

`~/.claude/scripts/codex-fix.sh [--astra] <repo> <findings-file> [out]` takes findings and edits code
in an isolated `git worktree` under `~/.claude/worktrees/`, with `-s workspace-write`, after
installing the repo's npm packages (a fresh worktree has none, and a reproduction that fails for
that reason looks exactly like a real failure). The RUN never commits, pushes or merges — the diff
is the product. Removal is a separate step, `codex-fix.sh --cleanup <worktree>`, and it is not
optional: it takes the worktree **and** its DerivedData, ~5 GB per tree that built, which
`git worktree remove` never touches.

Why it is not a `--write` flag on `sol-review.sh`: a reviewer that writes reviews its own patch on
the next pass, and `sol-review.sh`'s prompt *forbids running tests* precisely because its sandbox is
read-only — flipping the sandbox would leave that sentence in the prompt after it stopped being
true. The write lane is also the only one that CAN satisfy the two-observations rule: in a read-only
sandbox the model cannot run the reproduction at all.

🔴 **The report's "verification observed" column is the model's account of its own run.** Verified
5.9.2026 on a planted off-by-one: the fix was correct and the table honest, but the check that
settled it was me running `python3 test_calc.py` in the worktree, not the row that said PASS.

⚠️ `fable` runs long (8–17 min on a large scope) and **sees the working tree, not HEAD** — commit
underneath it and it will say so and review the current state. The guard does **not** apply itself
through the Agent tool; put it in the prompt.

### ⚠️ The risk this transition creates by itself

Over the API, sol physically **could not** read my plan or `docs/`. With repo access it can — and
`audit-briefing` #1 says a reviewer who knows my reasoning does not verify it, it **rationalises**
it. Both wrappers therefore inject a ban on reading `CHANGELOG.md`, `KNOWN_BUGS.md`,
`AUDIT_BACKLOG.md`, `ROADMAP.md`, `ONDEVICE_TEST_QUEUE.md` and `docs/*_PLAN.md`.

**Without that ban this tool is WEAKER than the API variant it replaces.** Never bypass it with a
hand-rolled `codex exec` / `agy -p` that lacks the header.

#### 🔗 One source: `~/.claude/scripts/review-guard.md`

The shared header (the ban + "comments are my unverified claims" + "you are allowed to find
nothing") lives in **one file, never copied** — copies drift apart. Tool-specific parts (output
format, `grep` instead of `rg`, NET diff, line numbers) stay in each wrapper.

- **A missing or empty guard is a hard error — the wrapper runs nothing.** A guard that can be
  silently skipped is not a guard (`audit-briefing` #9c: a missing `+x` silently skipped a whole
  block).
- **`REVIEW_DRY_RUN=1 <wrapper> <mode> <repo> <brief>`** prints the assembled prompt and exits.
  It exists to confirm the guard **is actually in the prompt** — "the line is in the script" does
  not prove that.
- Verify by **mutation** too: hide `review-guard.md` and confirm the wrapper fails. A green check
  whose opposite you have never seen fail proves nothing.

### ⚠️ `agy` is corroboration, NEVER a standalone verifier

Tool access alone is not enough — `agy` has invented a symbol in a file it had opened 37 times, and
"disproved" a watchdog by pointing at the wrong code path. The tool-less sol got both right.

Asymmetry: *a bad first pass corrects itself downstream; a bad verifier never hits anything.*
So `agy` takes **`survey`, not `verify`**, and its contested claims are **always** grepped and
checked against the conversation DB.

### ⛔ What this does NOT change: audits of existing code

| Type of work | Who finds the findings |
|---|---|
| **Audit of existing code** (bug hunting) | **4 parallel Claude grep agents with DIFFERENT optics** — correctness / race-crash / money-sync / hostile (as `audit-briefing` §3 defines them) |
| **Review of my own fixes** | **sol** |

They are two different jobs. Narrowing audits to sol+agy loses the **hostile optic**, which
`audit-briefing` #3 names as the one that produced a novel finding on days nothing else did. The
6–7 LLM panel below and the Claude grep agents stay unchanged for audits.

---

## Reviewers for AUDITS and broad checks (ALWAYS 6 LLMs in parallel, +GLM-5.2 = 7 for T3)

| LLM | Model | Endpoint | Timeout | Focus |
|---|---|---|---|---|
| **GPT Codex** | `gpt-5.3-codex` | `/v1/responses` | 300 s | Diff semantics, line-level bugs, concurrency, races, architecture |
| **Gemini 3.1 Pro** | `gemini-3.1-pro-preview` | **Vertex AI global** | 600 s | Completeness, edge cases, platform-specific |
| **Grok Code** | `grok-code-fast-1` | `api.x.ai/v1/chat/completions` (+ User-Agent!) | 300 s | Security, performance, reasoning trace |
| **grok-build-0.1** (mandatory from T2) | `grok-build-0.1` | `api.x.ai/v1/chat/completions` (+ User-Agent!) | 300 s | Coding/implementation view, agentic. Does not hallucinate paths; **estimates line numbers**. `max_tokens` 16384–20000 |
| **DeepSeek V3.2** | `deepseek/deepseek-v3.2` | OpenRouter | 300 s | Code, competitive coding, cheap alternative view |
| **GLM-5.2** (z.ai, trial from T3) | `glm-5.2` (thinking ON) | `api.z.ai/api/paas/v4/chat/completions` | 900 s | Alternative reasoning, **realistic severity calibration**, does not hallucinate paths. `thinking:{type:enabled}`, `max_tokens` **65536** — 32768 returns an EMPTY answer on a large review (measured 20.9.2026 on a 17K-token review prompt: 32768 → all 32768 tokens went to reasoning, finish reason `length`, empty `content`, 450 s; 65536 → finish reason `stop` at 40822 completion tokens (37123 reasoning), 538 s). Slow (450–540 s; the 900 s timeout is right) |
| **Sonnet 5** | Agent tool (`subagent_type=Plan`, `model: sonnet`) | Claude Code | 300 s | Code-level bugs, Swift gotchas, line-by-line. **Has a grep tool — best at hunt-for-missed-sites audits** |
| **Premium escalation** (opt-in) | `gpt-5.6-sol` | `/v1/chat/completions` (`temperature`=1) | 600 s | Only on request or a genuinely extreme problem |
| **Extra-premium** (opt-in, 🔴 explicit ask only) | `gpt-6-astra` | Codex CLI via `astra-review.sh`, or `/v1/chat/completions` | 45 min | $10/$50 per 1M — 2.5× sol *(verified 5.9.2026: developers.openai.com model page)*. Never reach for it after a weak sol run; that is exactly the reflex the gate exists to stop |

**Default panel (6):** GPT Codex + Gemini + Grok Code + grok-build-0.1 + DeepSeek + Sonnet.
**NEVER** silently swap one of them for premium or true-pro.

- **ALWAYS all 6 in parallel** (+GLM-5.2 as the 7th in a full T3 panel). Skip none — each has a
  different blind spot.
- **ALWAYS Vertex AI for Gemini**, never AI Studio (AI Studio has outages). A hook enforces this.
- **Grok + grok-build-0.1: User-Agent MANDATORY** — without it Cloudflare 1010 blocks you.
  (GLM/z.ai does not need one.)
- **DeepSeek via OpenRouter** — key in skill `llm-apis` → `references/openrouter.md`.
  **GLM-5.2: key in `~/.private_keys/zai.env`.**
- **grok-build-0.1** and **GLM-5.2** are on trial — if they stop producing unique findings,
  degrade them to opt-in.

## `agy` (Antigravity CLI / Gemini) — operational notes

Satisfies `audit-briefing` #4 (*at least one reviewer must have tools*). Has repo access and grep,
so it **does not hallucinate paths or symbols**. Runs on the Google account quota, not Vertex/GCP
billing.

```bash
~/.claude/scripts/agy-review.sh survey <repo> <brief-file> [out]   # first pass
~/.claude/scripts/agy-review.sh verify <repo> <brief-file> [out]   # claim checking — see caveat above
```

Three traps (the wrapper handles them; a hand-rolled call must replicate them):

1. **`--add-dir <repo>` is MANDATORY** — it ignores `cd`, and otherwise audits an empty scratch
   directory while answering confidently about nothing.
2. **Without an enforced evidence format it throws the work away.** Requiring "a table of ≥25 rows;
   a bare verdict is an invalid answer" turned a one-line summary into 29 cited claims for the same
   amount of work.
3. **It estimates line numbers** (20–30 drift) but cites symbols correctly. Take the symbols,
   ignore the lines.

**Headless permissions:** tool calls are auto-denied in `-p` mode unless allowed in
`~/.gemini/antigravity-cli/settings.json`. `--dangerously-skip-permissions` also approves
**writes** → never use it for an audit; `--mode plan` is the safety net.

**Verifying it actually worked — MANDATORY, not only on suspicion.** It ignores coverage ledgers
and `UNREAD` markers even when the brief demands them, so it will never tell you what it skipped.
The conversation DB is the only way to find out:

```bash
DB=$(ls -t ~/.gemini/antigravity-cli/conversations/*.db | head -1)
python3 -c "
import sqlite3,re,collections
c=sqlite3.connect('file:$DB?mode=ro',uri=True); seen=collections.Counter()
for (p,) in c.execute('select step_payload from steps'):
    if p:
        for m in re.findall(r'[A-Za-z0-9_/]+\.swift', p.decode('utf-8','replace')): seen[m.split('/')[-1]]+=1
for k,v in seen.most_common(15): print(f'{v:5}  {k}')"
```

---

## Procedure

### 1. Identify components

Order by criticality: CRITICAL (state management, auth, data pipeline, audio engine) → HIGH
(networking, sync, error handling) → MEDIUM (UI, settings, analytics) → LOW (utils, constants,
extensions).

### 2. Review one component

```
a) Prepare context:
   - what the code does (2–3 sentences)
   - what to check (numbered list, 5–10 points)
   - WHOLE files, not snippets

b) Send to the panel IN PARALLEL, all run_in_background
   - Gemini via Vertex AI OAuth2 SA (references/gemini-vertex.md)
   - Grok: User-Agent header (references/xai-grok.md)
   - DeepSeek: via OpenRouter (references/openrouter.md)

c) Synthesise:
   - table: finding | who | severity
   - consensus (2+ LLMs) = higher confidence
   - single LLM = verify against the code

d) MY OWN ANALYSIS against the code:
   - read the relevant lines
   - judge the real severity (LLMs routinely overrate)
   - check for false positives (the LLM lacks context)
   - final table with MY severity

e) NO CHANGES WITHOUT THE USER'S CONSENT
   - present findings + prioritisation, wait for go/no-go
```

### 3. Fixes

```
a) Implement the approved fixes
b) Commit describing what and why (reference the LLM source)
c) RE-REVIEW: send the fixed files back
   - context: "RE-REVIEW after N fixes. Verify + look for regressions."
   - goal: "ALL FIXES VERIFIED" from everyone
d) If re-review finds something new → fix → re-review again
e) Max 3 iterations, then escalate to the user
```

### 4. Next component

Repeat. Do not touch another component's files without reviewing them.

---

## Prompt template

```
You are a senior [ROLE]. Review [FILES] ([LINES] lines).

## What this code does
[2-3 sentences of context]

## What to check
1. [specific point]
2. [specific point]

Rate findings: CRITICAL / HIGH / MEDIUM / LOW. Line numbers.

## Full code
[CODE]
```

### Mandatory review dimensions (omit them and the LLM misses them)

Add these *explicitly* to **What to check** — an LLM will not cover them on its own.

#### SwiftUI specific

When reviewing a View struct, always include:

- **Observation dependency graph.** "Does this View re-render when every read external state publishes? For each `@Published` property accessed inside `var body`, a computed property, or a `@ViewBuilder` function: is there an `@ObservedObject` / `@StateObject` / `@EnvironmentObject` that forms a SwiftUI dependency edge? A bare reference like `SomeClass.shared.publishedProperty` does NOT create an edge — flag as CRITICAL."
- **Singleton reads in reactive context.** "Any `X.shared.y` access inside a body/computed/viewBuilder that is NOT in a `.onAppear` / Button action / event handler is suspect. Trace the property wrapper chain."
- **StoreKit async race.** "If the View reads entitlement/subscription state, does it correctly handle the ~500-1000 ms cold-launch window where `loadPurchases()` is still pending? Does the body re-evaluate after load completes?"
- **Async mutation in init, sync read in body.** "Does the ObservableObject's `init` kick off `Task { self.something = await … }` AND is `something` read during `body` evaluation of the owning view? If `something` is a bare `var` (not `@Published`), the late async write is silently dropped — the first body pass reads the initial value and SwiftUI never rebuilds. Flag as CRITICAL. Applies especially to cached snapshots, resolvers, and any value sourced from an `await` in init. Fix: mark the property `@Published` AND seed it synchronously where possible (e.g. from a singleton that has already initialized at launch)."
- **Parallel `.sheet` modifiers on the same view.** "SwiftUI only renders one `.sheet` per view at a time. Two or more `.sheet(isPresented:)` / `.sheet(item:)` modifiers chained on the same view race on iOS 26 — the presentation may flash and dismiss, or the `onAppear` hook may never fire. Fix: unify into a single `.sheet(item:)` driven by an `Identifiable` enum (`.detail(id)`, `.paywall`, etc.)."
- **`_UIHostingView.__deinit` teardown race on identity-swapping body branches.** "For every View that observes a singleton `ObservableObject` via `@ObservedObject` / `@EnvironmentObject`: does its `body` have branches that return *fundamentally different view types* (Button ↔ `EmptyView()`, Section A ↔ Section B, VStack banner ↔ nothing) gated on a `@Published` property that can flip async (StoreKit `loadPurchases()`, WCSession delegate, BLE delegate, NotificationCenter, background fetch)? If the view is mounted inside a container with concurrent animations (sheet presentation, `.safeAreaInset`, `.transition`, NavigationStack push, parent `.animation(value:)`), the reactive body flip causes SwiftUI to tear down one `_UIHostingView` while another animation is in flight — `ViewGraphHost.clearDisplayLink` races `_UIHostingView.__deinit` during `objc_autoreleasePoolPop`. Flag as HIGH. Fix: wrap the conditional in `Group { ... }.transaction(value: <gate-expr>) { $0.animation = nil }` for snap-swap semantics. **IMPORTANT: use the value-scoped overload**, not unscoped `.transaction { }` — the latter propagates animation suppression to ALL child transactions, killing user-initiated Toggle/Picker/Button animations inside the subtree (user-visible UX regression). Value expression must be `Equatable` — use `Bool` for simple gates, an `Int` bit-pack for multi-flag gates, or synthesize `Equatable` on an enum.
  iOS 17+. This mistake was caught only by a fresh clean-context Opus audit — a 3-LLM panel + Sonnet phase 5 both approved the unscoped form. **Pre-flight audit when adding `@ObservedObject` on a singleton:** (a) what new body flips does this enable? (b) does body have identity-swapping branches? (c) mounted inside container with parallel animations? (d) can the singleton's `@Published` flip async? If ≥3 YES, apply the `Group + .transaction` wrap preemptively."
- **Config mutation without emission.** "If `<ConfigStore>.$config.removeDuplicates()` is the only propagation, a no-op config merge stops the re-render chain. Are there other state changes that need to fan out (banners, gates) that won't get notified?"
- **Computed property stability.** "Can this computed property return different values across calls without any `@Published` change? If yes, SwiftUI never re-computes it."

#### Concurrency specific (Swift 6, strict)

- **Await suspension vs atomicity.** "For every `await` inside a @MainActor method: what state mutations happen before/after? Can another MainActor task run between them and observe an inconsistent intermediate state?"
- **`nonisolated` crossings.** "Any `nonisolated` method reading @MainActor-isolated state? Requires `assumeIsolated` or an explicit hop."
- **Delegate callbacks.** "AVAudio/URLSession/WatchConnectivity delegates: on which queue/actor do they fire? Is the handler `@MainActor`-annotated or does it hop?"

#### Race / cancellation

- **Task cancel propagation.** "For every `Task {}`: does child cancellation propagate? Are there `Task.isCancelled` or `try Task.checkCancellation()` checkpoints at `await` sites?"
- **Weak vs value capture in closures stored in dictionaries.** "A dict entry holding `[weak transfer]` may never fire the cleanup branch if the weak reference nils first. Prefer `ObjectIdentifier(transfer)` value capture."

#### Architecture / data flow

- **Single source of truth.** "If this view reads X from two places (shared singleton + config snapshot), which wins? Both observed? Stale-cache risk?"
- **Merge-vs-overwrite.** "When writing snapshot/state that multiple paths can also write: is there a pure `merge(a, b) -> c` gate? Or a last-writer-wins race window?"

### Prompt template — SwiftUI CRITICAL addendum

When the reviewed code contains `struct X: View`, APPEND this to **What to check**:

```
N. SwiftUI observation dependency graph:
   - For EACH `@Published` property read inside `var body`, a computed
     property, or a `@ViewBuilder` function: confirm there is an
     `@ObservedObject`, `@StateObject`, or `@EnvironmentObject` property
     wrapper on the **same struct** that owns the source class. A bare
     `X.shared.y` reference does NOT create a SwiftUI dependency edge.
   - Flag as CRITICAL any View that reads `<PurchaseManager>.shared.<entitlementState>`,
     `<PurchaseManager>.shared.<hasAccess>()`, or similar shared ObservableObject
     properties inside reactive context without a matching observer.
   - Event-handler closures (`.onAppear { }`, Button action, `.onChange { }`)
     are safe — they re-run per event regardless of SwiftUI observation.
   - Check specifically: what happens on cold launch when StoreKit takes
     500-1000 ms to load? Does the View still show correct UI after load
     completes, or does it cache pre-load state permanently?
```

### Re-review template

```
RE-REVIEW after N fixes.

Fixes applied:
1. [fix description]
2. [fix description]

Verify all N fixes. Look for regressions.
Rate: CRITICAL / HIGH / MEDIUM / LOW. If clean: "ALL FIXES VERIFIED."
```

---

## Severity calibration

| LLM severity | Often really | Why |
|---|---|---|
| CRITICAL | HIGH/MEDIUM | LLMs have no runtime context and overrate edge cases |
| HIGH | MEDIUM | Depends on how hot the code path is |
| MEDIUM | MEDIUM/LOW | Usually legitimate |
| LOW | LOW | Usually nice-to-have |

**Lower the severity when:** the LLM does not know the whole project (another file handles it); the
edge case needs extremely specific timing; the path is legacy or unused; it is a design decision,
not a bug.

**Raise it when:** 3 LLMs agree on the same finding; it sits in a hot path (every request, every
audio buffer); memory leak / crash / data loss; security (credential leak, auth bypass).

## Anti-patterns

- NEVER send secrets or API keys in a prompt
- NEVER change code without the user's consent
- NEVER accept a finding without verifying it against the code yourself
- NEVER use AI Studio for Gemini (outages)
- NEVER send only a diff — whole files for full context
- NEVER ignore a false positive silently — document why it was downgraded

## Gemini Vertex AI — quick reference

```python
# OAuth2 token
import jwt as pyjwt
with open('path/to/sa.json') as f: sa = json.load(f)
now = int(time.time())
token = pyjwt.encode({
    "iss": sa["client_email"],
    "scope": "https://www.googleapis.com/auth/cloud-platform",
    "aud": "https://oauth2.googleapis.com/token",
    "iat": now, "exp": now + 3600
}, sa["private_key"], algorithm="RS256")

# Token exchange
data = f"grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion={token}".encode()
access_token = json.loads(urlopen(Request("https://oauth2.googleapis.com/token", data=data,
    headers={"Content-Type":"application/x-www-form-urlencoded"})).read())["access_token"]

# Call — GLOBAL endpoint for 3.x preview
url = f"https://aiplatform.googleapis.com/v1/projects/{sa['project_id']}/locations/global/publishers/google/models/gemini-3.1-pro-preview:generateContent"
```
