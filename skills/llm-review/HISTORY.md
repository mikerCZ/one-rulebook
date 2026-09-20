# llm-review — archived evidence

Moved out of `SKILL.md` on 4.8.2026. **Nothing deleted.** These are the dated observations the
rules in `SKILL.md` were derived from.

> **Kept in Czech, verbatim, from 4.8.2026 until 20.9.2026.** It is an evidence archive, not
> instructions, and the ground for leaving it untranslated was that a translation would re-stamp
> measurements nobody is going to re-run — the exact failure mode the "no bulk rewrite" rule
> exists to prevent. On 20.9.2026 the operator decided the instruction layer is translated in
> place for the public export, and this file with it (translation brief, 20.9.2026): every date,
> number, model id, price and count is unchanged, and the claims go through an independent verify
> pass. The Czech original stays in the private repo's git history. The English rules distilled
> from this evidence live in `SKILL.md`; this is only the record of what they were based on.
<!-- TRANSLATOR: header rewritten — the original said the file is deliberately kept in Czech and
     carried the language hook's escape-hatch marker; the translation makes that sentence false, so
     it is in past tense and the marker is dropped (a literal marker anywhere in the written content
     switches the instructions-in-english hook off). Reviewer decides. -->

Read this when a rule in `SKILL.md` is being questioned and you need to know its basis.

---

## Why `sol` + `agy` as the default for reviewing MY work (20.7.2026)

- **sol is strongest on my own work.** On 20.7.2026 it caught **4 of 5** of my attempted fixes
- **Over the API it sees only what I paste in.** The same day it answered ~15× "not visible in the
  provided code" and I had to re-verify every such sentence by hand. With repo access that class
  disappears.
- **Both run on the SUBSCRIPTION, not on API billing.** Verified: `~/.codex/auth.json` has
  `auth_mode: chatgpt` and `OPENAI_API_KEY: None`; `agy` runs on the Google account's quota. A
  smoke test of 34 418 tokens cost marginally zero. **That drops the only argument for
  `gpt-5.3-codex`** as the default review model — its $0.12/review competed on price and on price
  alone.

## Why the guard lives in one file (23.7.2026)

Until 23.7.2026 the ban on reading rationale documents applied to **`sol` only**. `agy` did not
have it and nobody noticed, because both wrappers looked finished. It was caught only at the
moment I had written a bug analysis into a project dashboard — including the list of
hypotheses already ruled out — and a few minutes later wanted to launch `agy` to look for the
cause of the same bug. It would have read my conclusions and confirmed them to me.


## Why audits stay on the panel and the grep agents (20.7.2026)


If audits were narrowed to sol+agy, the **hostile optic** would be lost — the one that
`audit-briefing` #3 names as the only one that on some days produced a new finding.

## `agy` — forced coverage works (20.7.2026)

- Debut: 104 steps and 11 files actually grepped → output "The docs perfectly match the code."
  After adding "a table of ≥25 rows, a bare verdict = an invalid response" → 29 claims with
  citations. Same work, different output.
- It ignores the coverage ledger and the `UNREAD` markers even when the brief explicitly requires
  them (2/2 runs). So it will never tell you by itself what it skipped — the DB is the only way.
- The debut doc-vs-code audit ended with 0 mismatches, the same as an
  independent Sonnet — but both got the same closed question, so that is correlated agreement,
  not proof (`audit-briefing` #3).


## Statistics from the 22.4.2026 audit-follow-up session

- The 5-LLM panel with 4 external models + Sonnet found 14 sites in total
- **Sonnet (with the grep tool) alone found all 3 CRITICAL**
- **GPT-5.4-pro / Gemini / DeepSeek hallucinated** several non-existent file paths
  — no tool access for verification
- **GPT-5.3-codex did as well as pro** in the plan review — not worth 13× the price

## Statistics from the 28.3.2026 session

- 4 LLMs in the panel: GPT-5.3 Codex, Gemini 3.1 Pro (Vertex), Grok Code, Sonnet 4.6 — plus DeepSeek as the fifth, cheap slot (the bullets below list all five)
- **Gemini** best at platform-specific bugs
- **GPT** best at concurrency/architecture
- **Sonnet** best at line-by-line thoroughness
- **Grok** fastest, good at security review, reasoning trace valuable
- **DeepSeek** cheap, strong on code, competitive coding #1
- **NEVER skip any LLM** — each found a different class of problem (the private record names them)

## History of price discipline

A week of reviews once cost us ~**$70 USD** through careless use of `gpt-5.4-pro` (22.4.2026).
Since 11.7.2026 the premium escalation is `gpt-5.6-sol` ($5/$30, ~3× codex instead of ~13×) —
true pro models stopped being the default escalation. Since 4.8.2026 `sol` is the default
outright and only the route (Codex CLI vs API) is decided, by the remaining quota.

| Model | Input/1M | Output/1M | Typical review (3K in / 8K out) |
|---|---|---|---|
| `gpt-5.3-codex` | $1.75 | $14 | $0.117 |
| `gpt-5.6-sol` | $5 | $30 | $0.255 at 3K/8K by these prices; the ~$0.35 quoted elsewhere corresponds to ~11K of output, which sol's longer reviews reach (derivation 20.9.2026) |
| `gpt-5.5-pro` / `gpt-5.4-pro` | $30 | $180 | $1.53 |

## 20.9.2026 — GLM-5.2 `max_tokens`, and two confident false findings

One review prompt (three shell scripts, 1132 lines, 17 279 prompt tokens), thinking ON:

| `max_tokens` | finish | completion tokens | reasoning tokens | `content` | wall |
|---|---|---|---|---|---|
| 32768 | `length` | 32768 | 32768 | empty | 450 s |
| 65536 | `stop` | 40822 | 37123 | 12 142 chars, 14 findings | 538 s |

So 32768 is not a budget for a large review, it is an empty answer, and the 900 s timeout in the
panel table is the right order (the 180 s in the reference examples is for a question).

Of the 14 findings, two were confident and false: "`\s` in grep ERE is not portable, the hook
does not fire on macOS at all" (the hook had fired on this Mac all day — verified by its BLOCKED lines in this session) and "UTF-8 characters in a bracket
expression do not match under BSD awk" (they do — probed). Checking the second one found a REAL
gap next to it: the Czech universal-word patterns were matched against the original-case line, so
a sentence-initial "Jediná" / "Všechny" / "Žádný" passed (measured with five probe lines). Fixed the same day, fixture cases added.
The rest were real but low (a lock path in the shared `/tmp`, a tee that is not waited for, an
unreadable `hooks.json` reported as an untrusted hook, word-splitting on paths with spaces).
