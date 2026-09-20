---
name: dev-flow
description: "Orchestrated development process — 6 phases, T1/T2/T3 risk tiering, cross-cutting checklist (analytics, localization, Watch parity, migration), parallel LLM review. Load BEFORE writing code for any non-trivial change — more than 5 files, unclear scope, or anything touching security, billing, the data model or an API contract."
---

# Dev Flow — Orchestrated development process

## Overview

Opus 4.6 is the **main orchestrator** — it analyses, plans, delegates, checks. It never implements blind. Non-trivial changes go through a structured process whose depth matches the risk.

---

## Risk Tiering — what to use when

| Tier | Criteria | Phases | LLM review |
|------|----------|------|------------|
| **T1 — Small** | 1-5 files, clear scope, no API/model change | 1 → 2 → 4 → 6 | None (Opus 4.6 self-review only) |
| **T2 — Medium** | 6-15 files, or unclear scope, or security-adjacent | 1 → 2 → 3(simplified) → 4 → 5(simplified) → 6 | 3 LLMs (GPT-5.3-codex + grok-build-0.1 + Sonnet 5 Task) |
| **T3 — Large** | >15 files, API contract, data model, auth flow, billing | 1 → 2 → 3 → 4 → 5 → 6 (full flow) | 5 LLMs in parallel (+ grok-build-0.1 + GLM-5.2 z.ai trial) + Sonnet 5 Task |

**Always T3:** a change to the encryption scheme, Keychain, iCloud sync format, API contract, billing/trial logic.
**T3 additionally requires:** the user's consent (human gate) before Phase 4 starts.

**Do not use the flow for:** one-line fixes, config changes, purely cosmetic edits.

---

## Phase 1: ANALYSIS (Opus 4.6 — main context)

**Goal:** Understand the scope, identify the affected areas, determine the Tier.

### Steps:
1. **Load the relevant files** — Read/Grep/Glob, never change without reading
2. **Determine the Tier** (T1/T2/T3) per the table above
3. **Identify cross-cutting concerns** — checklist:

| Concern | Check question | Action if YES |
|---------|-----------------|-----------------|
| **Analytics** | Am I adding/changing an error path? A user-facing action? | success + error events (model, statusCode, errorCode, device, mode, proStatus) |
| **Localization** | Am I adding/changing user-facing text? | the project's string generator, regeneration, every supported language |
| **Watch parity** | Am I changing a feature available on the Watch? | Implement on both platforms |
| **Security** | Auth flow, API keys, encryption? | Security review mandatory (→ T3) |
| **PRO/FREE** | Trial limit, the free-tier limits type | Verify the counting logic |
| **Accessibility** | New UI elements? | VoiceOver, Dynamic Type, Reduced Motion |
| **Migration** | Am I changing the data model, Keychain schema, iCloud sync? | Migration + backward compatibility |
| **Performance** | Watch battery, memory, network heavy? | Performance assessment |
| **CHANGELOG** | Significant change? | CHANGELOG.md |

4. **Map the dependencies** — which files must change together
5. **Record the git rev** — `git rev-parse HEAD` as the baseline for validation

### Output: A structured overview of the scope + Tier + list of concerns + baseline rev

---

## Phase 2: PLAN (Opus 4.6 — main context)

**Goal:** A concrete, unambiguous implementation plan.

### Plan structure:

```markdown
## Context
Why we are making the change, what problem it solves.

## Tier: T1/T2/T3

## Changes (per file)
### 1. FileA.swift
- Line X: add/change/delete — concrete code
- Line Y: ...

### 2. FileB.swift
- ...

## Cross-cutting
- Analytics: [concrete events + parameters]
- Localization: [concrete new strings]
- Watch: [what must change on the Watch]
- Migration: [migration logic if relevant]

## Affected files (table)
| File | Changes |
|--------|-------|

## Rollback plan (T2/T3)
- Baseline tag: `pre-{feature-name}`
- Revert strategy: git revert / feature flag
- Blast radius: [list of affected features]

## Verification
1. Build iOS + Watch (sequentially)
2. Tests: [concrete test scenarios]
3. Specific verifications
```

### Requirements for the plan:
- **Concrete lines and code** — not "add error handling" but the exact snippet
- **Complete** — includes ALL cross-cutting concerns from Phase 1
- **Sequenced** — the order of changes respects the dependencies
- **Testable** — clear verification steps
- **Rollback-ready** (T2/T3) — how to revert the changes

---

## Phase 3: CRITICAL PLAN REVIEW (parallel LLM review)

**Only for T2 (simplified) and T3 (full).**

**Goal:** Uncover errors, edge cases, security problems BEFORE implementation.

### Pre-send sanitisation (MANDATORY):
1. `grep -rn "API_KEY\|SECRET\|PASSWORD\|PRIVATE\|Bearer" <<< "$PROMPT"` — no secrets
2. Remove absolute paths (`/Users/...` → relative)
3. Verify the prompt does not contain `.env`, `key.properties`, credentials

### Orchestration:

> **COST DISCIPLINE (22.4.2026, updated 11.7.2026, superseded 20.7.2026 by the note below):** until 20.7.2026 the default GPT model for Phase 3 and Phase 5 was `gpt-5.3-codex` (~$0.12/review) with `gpt-5.6-sol` (~$0.35/review, ~3× codex, chat completions, `temperature`=1) as the opt-in escalation that had replaced `gpt-5.4-pro` on 11.7.2026. Since 20.7.2026 `gpt-5.6-sol` over the Codex CLI IS the default (CLAUDE.md, "Which model reviews"); what still holds from this note: the true pro models `gpt-5.5-pro`/`gpt-5.4-pro` (~$1.53, ~13×) and `gpt-6-astra` are used on explicit request alone — see skill `llm-review`.

> ⭐ **Since 20.7.2026 the default for Phase 3 and Phase 5 is: `sol` via Codex + `agy`** (both tool-armed,
> see `skills/llm-review/SKILL.md` § Default for reviewing MY OWN work). The table below is the **escalation** for T3 or
> for cases where I want a wider set of lenses — not the first choice.
>
> ```bash
> ~/.claude/scripts/sol-review.sh plan   <repo> <brief> [out]   # Phase 3
> ~/.claude/scripts/sol-review.sh review <repo> <brief> [out]   # Phase 5
> ~/.claude/scripts/agy-review.sh survey <repo> <brief> [out]   # corroboration
> ```
>
> **Do not call `codex exec` by hand** — the wrapper inserts the ban on reading rationale documents
> (`CHANGELOG`, `KNOWN_BUGS`, `AUDIT_BACKLOG`, `ROADMAP`, `*_PLAN.md`). With repo access the reviewer
> would otherwise read them and start rationalising my reasoning instead of verifying it
> (`skills/audit-briefing/SKILL.md` #1). The sandbox is `-s read-only`; do not override it.

| Tier | Reviewers (escalation / wide coverage) |
|------|-----------|
| **T2** | GPT-5.3-codex + **grok-build-0.1** + Sonnet 5 Task |
| **T3** | GPT-5.3-codex + Gemini 3.1 Pro + Grok Code + **grok-build-0.1** + MiniMax M3 + **GLM-5.2 (z.ai, trial)** + Sonnet 5 Task |

⛔ **Audits of existing code are not changed by this.** There the parallel Claude grep agents
with different lenses (correctness / race-crash / money-sync / hostile, as `audit-briefing` defines them) remain — on 20.7.2026 they produced
most of the findings, while sol was strongest at reviewing my own fixes. Two different jobs.

| LLM | Model | Focus |
|-----|-------|-------|
| **GPT-5.3 Codex** (default plan + code review) | `gpt-5.3-codex` via `/v1/responses` (Responses API) | Diff semantics, line-level bugs, edge cases, race conditions, architecture |
| **Gemini 3.1 Pro** | `gemini-3.1-pro-preview` via **Vertex AI global** (preferred; AI Studio is an emergency fallback — the `gemini-vertex-only.sh` hook warns, it does not block) | Completeness, large input context (1M+ tokens), consistency |
| **Grok Code** | `grok-code-fast-1` | Security, performance, Swift-specific gotchas |
| **grok-build-0.1** (MANDATORY from T2, UNDER OBSERVATION) | `grok-build-0.1` via `/v1/chat/completions` (+ a browser-like User-Agent from Python: Cloudflare blocks the `Python-urllib/x.y` string urllib inserts by itself, measured 13.7.2026; the `grok-user-agent.sh` hook demands an explicit header) | Coding/implementation view, agentic. Does not hallucinate paths; estimates line numbers. max_tokens 16384–20000. See `xai-api.md` |
| **GLM-5.2** (z.ai, TRIAL from T3, UNDER OBSERVATION) | `glm-5.2` (thinking ON) via `api.z.ai/api/paas/v4/chat/completions` | Alternative reasoning view, realistic severity calibration (does not overstate CRITICAL), does not hallucinate paths/symbols, cheap (~$0.12). Slow (~500s with thinking). `thinking:{type:enabled}`, max_tokens **65536** (32768 empties the answer on a large review — measured 20.9.2026 on a 17K-token review prompt: 32768 → all 32768 tokens went to reasoning, finish reason `length`, empty `content`, 450 s; 65536 → finish reason `stop` at 40822 completion tokens (37123 reasoning), 538 s), User-Agent NOT needed. See skill `llm-apis`, `references/zai-glm.md` |
| **Sonnet 5** | Task tool (subagent_type=Plan) | Independent code-level review, grep tool — best at hunt-for-missed-sites audits |
| **GPT-5.6-sol** (premium escalation, opt-in only, ~3× codex) | `gpt-5.6-sol` via `/v1/chat/completions` (reasoning chat, `temperature`=1) | **Only on explicit request** or a genuinely extreme architectural problem where the cheaper models have repeatedly failed. **Ask the user** before deploying it. Replaced `gpt-5.4-pro` (11.7.2026); the true pro models `gpt-5.5-pro`/`gpt-5.4-pro` (Responses API) only on explicit request. |

### Prompt template — Phase 3 focus: DESIGN & ARCHITECTURE (IN ENGLISH):

```
You are a senior Swift/SwiftUI architect. Critically review this implementation plan.
Focus on DESIGN decisions, not code-level details.

## Plan
{PLAN}

## Relevant existing code
{CODE_SNIPPETS}

## Answer:
1. **Architecture** — is the approach sound? Better patterns?
2. **Race conditions** — concurrency, @MainActor, Sendable, async/await
3. **Missing changes** — files/components the plan should include but doesn't
4. **Security design** — auth bypass, data exposure, injection vectors
5. **Backward compatibility** — migration, data model versioning
6. **Analytics completeness** — missing events/parameters for error paths?

Be specific — show exactly what's wrong and how to fix it.
```

### LLM resilience:
- **Timeout per model:** 90s
- **Minimum to continue:** 2 answers (at least 1 must be GPT or Gemini)
- **Retry policy:** 1 retry with a 10s delay, then skip
- **If 3+ models fail:** abort, notify the user

### Processing the results:
1. Opus 4.6 waits for the answers (respecting the timeout)
2. Categorises the feedback: **must-fix** vs **nice-to-have**
3. On conflict: priority `security > correctness > data integrity > UX > style`
4. **Decision log:** Record the reason for every must-fix/waive
5. Updates the plan per the must-fix feedback
6. **Max 2 iterations** of Phase 2↔3. After the 2nd iteration → escalate to the user

### Go/No-Go criteria:

| Condition | Action |
|----------|------|
| Critical error in the plan (>=1) | Back to Phase 2 |
| Missing files (>=2) | Back to Phase 2 |
| Security concern (>=1) | Back to Phase 2 |
| Nice-to-have feedback | Document, continue |

---

## Phase 4: IMPLEMENTATION (Opus 4.6 agents)

**Goal:** A clean, complete implementation per the final plan.

### Pre-implementation (T2/T3):
- **Feature branch:** `git checkout -b feature/{name}` (never directly on main)
- Create a git tag: `git tag pre-{feature-name}`
- Verify the baseline rev: `git rev-parse HEAD` == the rev from Phase 1

### Strategy:
- **Sequential changes** (dependent files): Opus 4.6 implements directly
- **Independent changes** (separate concerns): parallel Task agents
- **After parallel tasks:** an integration build of the whole workspace + merge conflict check
- **Merge conflict handling:** If parallel agents edit overlapping files, Opus 4.6 resolves the conflicts manually before the build
- **Beware of git index.lock:** Parallel agents must not commit at the same time — sequential commits after all tasks have finished

### Implementation rules:
1. **Strictly per the plan** — no ad-hoc "improvements"
2. **Build after every logical group** — iOS build (the Watch builds automatically)
3. **Commit per coherent change set** — a logical unit, not after every file
4. **New warnings = must-fix** — do not commit with new warnings
5. **Conventional commit messages** — a lowercase prefix from `feat: fix: refactor: chore: docs: test: style: build: ci: perf:` (the set `conventional-commits.sh` accepts)

### Build workflow:
```
Edit files → xcodebuild iOS → fix warnings → commit
(the Watch builds automatically as a dependency)
```

---

## Phase 5: CODE & SECURITY REVIEW (parallel LLM review)

**Only for T2 (simplified) and T3 (full). Same tiering as Phase 3.**

**Goal:** Verify the quality of the implementation, find bugs and security issues.

### Pre-send sanitisation: Same as Phase 3 (secrets check).

### Orchestration:
Opus 4.6 sends the **git diff** + context + the **original plan** in parallel to the LLMs (per Tier).

### Prompt template — Phase 5 focus: CODE-LEVEL & SECURITY (IN ENGLISH):

```
You are a senior Swift/SwiftUI security auditor. Review this code diff.
Focus on CODE-LEVEL issues, not architecture (that was reviewed in plan phase).

## Original plan (intent)
{PLAN}

## Git diff
{DIFF}

## Context (relevant files)
{FULL_FILES_IF_NEEDED}

## Answer:
1. **Bugs** — off-by-one, nil handling, race conditions, memory leaks, retain cycles
2. **Security** — OWASP top 10, data exposure, injection, auth bypass
3. **Analytics** — missing parameters? Logging sensitive data (PII)?
4. **Performance** — unnecessary allocations, main thread blocking, battery impact
5. **Edge cases** — unexpected API response? Timeout? Nil? Network offline?
6. **Plan compliance** — does implementation match the plan's intent?

Be specific — line, problem, fix.
```

### Processing:
1. Categorise: **must-fix** vs **optional**
2. Must-fix → implement immediately
3. Optional → consider, log if appropriate
4. **Decision log:** Record why feedback was accepted/rejected

---

## Phase 6: VERIFICATION (Opus 4.6)

**Goal:** Verify that everything works, nothing is missing, everything is committed.

### Checklist:
1. **Build** — iOS clean build with no new warnings
2. **Project lints** — every static check the project keeps under `scripts/` must return 0 errors; the catch-class of a SwiftUI view-observation lint is a view reading singleton `@Published` state in a reactive context without an observation edge.
3. **Cross-cutting verification:**
   - Analytics: `grep` — no error event has <3 parameters, no PII
   - Localization: regenerate the string catalog if strings were added
   - Watch parity: verified if relevant
   - Migration: upgrade path tested if relevant
4. **Test matrix** (T2/T3):
   - Happy path works on iOS and Watch
   - Edge cases: timeout, nil response, network offline
   - PRO/FREE limits verified if relevant
   - **StoreKit async race** (T2/T3, if it touches entitlement/subscription): test a cold launch of a subscribed user — the UI must render correctly during the entitlement-load race window (hundreds of ms) AND AFTER completion.
5. **Performance** (T3): profile memory + battery impact if relevant
6. **Git** — everything committed and pushed
7. **CHANGELOG** — updated
8. **Memory** — MCP memory updated (if relevant)
9. **Post-deploy monitoring** (T3): after release verify the crash rate, analytics event flow, key KPIs for 24h

---

## Quick Reference — LLM choices by task

| Task | Primary model | Why |
|-------|---------------|------|
| **Plan review (Phase 3)** | **`sol` via Codex** (`sol-review.sh plan`) | Tool-armed → can find callers the plan says nothing about. Caught 4/5 of my mistakes (20.7.) |
| **Code review (Phase 5)** | **`sol` via Codex** (`sol-review.sh review`) | Without repo access it answered ~15× "not visible in the provided code"; with it that class disappears |
| **Second lens for both** | **`agy`** (`agy-review.sh survey`) | A different family, on the subscription. **Corroboration, not verification** — on 20.7. it hallucinated a symbol |
| **Fallback when the Codex quota is exhausted** | GPT-5.3 Codex (API) | Codex runs on the **ChatGPT subscription** (`auth_mode: chatgpt`), not on an API key — the quota has a ceiling, the API does not |
| **Cheap parallel slot in an audit panel** | GPT-5.3 Codex (API) | Codex CLI = one process; the API scales. In an audit I run 6 reviewers at once |
| Security audit | Grok Code Fast | Visible reasoning, security focus |
| Completeness / broad review | Gemini 3.1 Pro (Vertex AI) | 1M+ input context, wide coverage, stable Vertex |
| Hunt-for-missed-sites audit | Sonnet 5 (Task tool) | **Has a grep tool** — does not hallucinate file paths like external LLMs do |
| Alternative view | MiniMax M3 (OpenRouter) / **GLM-5.2 (z.ai, trial)** | A different architecture, fresh perspective. GLM-5.2: thinking ON, realistic severity calibration, cheap, slow |
| Implementation task | Sonnet 5 (Task tool) | Fast, precise, Claude ecosystem |
| Orchestration | Opus 4.6 (main) | Strongest reasoning, context |
| **Extreme architecture (opt-in)** | `gpt-6-astra` via `astra-review.sh --human-asked`, or the true pro models over the API | 2.5× sol (astra) to ~13× codex (pro). On the operator's explicit request alone — a weak sol run is not a reason to escalate (CLAUDE.md red lines). |

## Parallel LLM review — implementation pattern

```
1. Prepare the prompt (plan/diff + context + questions)
2. Sanitisation: secrets check, absolute paths
3. Launch in parallel (per Tier):
   - Bash: curl GPT-5.3-codex Responses API (default for Phase 3 and 5) → run_in_background
   - Bash: curl grok-build-0.1 (MANDATORY from T2, + User-Agent!)        → run_in_background (see skill `llm-apis`, `references/xai-grok.md`)
   - Bash: Gemini 3.1 Pro via VERTEX AI (OAuth2)  → run_in_background (see skill `llm-apis`, `references/gemini-vertex.md`) [T3]
   - Bash: curl Grok Code Fast                    → run_in_background [T3]
   - Bash: curl MiniMax M3 (OpenRouter)         → run_in_background [T3]
   - Bash: python GLM-5.2 (z.ai, thinking ON, key from ~/.private_keys/zai.env) → run_in_background [T3, trial] (see skill `llm-apis`, `references/zai-glm.md`)
   - Task: Sonnet 5 agent (subagent_type=Plan)  → run_in_background
   - **NEVER** automatically the premium `gpt-5.6-sol` or the true pro `gpt-5.5-pro`/`gpt-5.4-pro` — only on explicit request (ask the user).
4. Timeout: 900s for GLM-5.2 (thinking — ~500s in practice), 180s for Gemini Vertex, 90s for the others, min 2 answers to continue
5. Synthesise the feedback + decision log
6. Decide: continue / go back (max 2 iterations)
```

## Anti-patterns (FORBIDDEN)

- Implementing without reading the existing code
- Skipping analytics on error paths
- Skipping localization of user-facing texts
- Ignoring LLM review feedback without an explanation (decision log)
- Committing without a successful build
- Committing with new warnings
- Pushing a project that has no `CHANGELOG.md` (hook-enforced), or pushing a significant change without a new entry (policy — the hook checks the file exists, not that it grew)
- A workaround instead of a fix (without explicit consent)
- Parallel xcodebuild (DerivedData lock)
- Sending secrets/API keys in prompts to external LLMs (policy; `check-secrets-in-llm.sh` catches known secret-name patterns and private-key markers, not arbitrary credentials)
- Logging PII/secrets into analytics or crash logs
- Changing an API contract without a versioning/deprecation plan
- A schema change without a migration + rollback plan
- "The LLM said so" without reproducible evidence
- Scope creep during implementation (strictly per the plan)
- Large commits (>500 lines of diff) without a logical reason
- Over-reliance on the LLM — always verify with a build and a test, not just "the LLM had no objections"
- Incomplete context in the LLM prompt — send whole relevant files, not isolated snippets
- Committing T2/T3 changes directly on main — always a feature branch
