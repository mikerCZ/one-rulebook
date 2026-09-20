# one-rulebook

**One rulebook, every agent.** A working configuration for running [Claude Code](https://claude.com/claude-code)
and [OpenAI Codex CLI](https://developers.openai.com/codex) side by side on one machine — two
Claude subscriptions in two profiles, Codex on its own subscription, Google's Antigravity CLI as a
third optic — with:

- **one instruction file** (`CLAUDE.md`) that the Codex side is generated from, so the two agents
  cannot drift;
- **hooks that enforce the rules mechanically** — commit-message shape, "a claim carries its
  evidence", no secrets in a prompt to an external model, no two `xcodebuild`s at once, no rsync
  mirror without a seatbelt — and that read both hosts' payloads (Claude's `Edit`/`Write`, Codex's
  `apply_patch`);
- **review and fix lanes as plain shell scripts** — a read-only reviewer, a fixer that works in an
  isolated worktree and hands back an uncommitted diff, and a premium lane behind a gate that is a
  claim about the human, not a switch;
- **quota instruments** for both subscriptions, profile-aware, and a statusline that shows them;
- **process skills** written from the incidents that produced them: how to brief a reviewer, how to
  delegate a multi-hour series to an agent unattended, how to share one repo between two live
  sessions, how to call a panel of foreign models.

The dated notes record measurements about the tools (bash, git, macOS, the Codex CLI, the hooks)
made on the author's machine, on that day. Re-measure before relying on one.

## The four principles the whole thing rests on

1. **A fix is two observations, not an argument.** Before you write "fixed", you have the failure
   reproduced and the same observation after the change, now negative. Without the first it is a
   hypothesis — say so. This applies to a reviewer's finding *and* to a reviewer's approval.
2. **A claim carries its evidence, or it does not get written.** In comments, commit messages and
   docs, a universal claim ("only", "never", "all N sites") carries `(verified: …)` inline or is
   reworded into a description. A pre-commit hook greps for the shapes it can see.
3. **Finder and fixer are two runs.** A reviewer that writes reviews its own patch on the next
   pass. `sol-review.sh` is read-only by construction; `codex-fix.sh` writes in a worktree and
   commits nothing; an independent layer reads the diff *after* the fixer.
4. **One writer per target.** `~/.codex/AGENTS.md` is generated, not hand-edited; skills and hooks are
   symlinks to one source; the sync script reports drift instead of silently re-copying, and
   refuses to overwrite a target that lost its generator marker.

`CLAUDE.md` is the full rulebook; `skills/` hold the detailed procedures and load on demand.

## What is inside

| Directory | What | Read first |
|---|---|---|
| `CLAUDE.md` | the rulebook — install as `~/.claude/CLAUDE.md`, fill in the operator section | itself |
| `hooks/` | 13 PreToolUse / SessionStart / PreCompact / SessionEnd hooks + `lib/hook-targets.py` (normalises Claude and Codex payloads) + a both-direction fixture suite | `hooks/tests/test-hooks.sh` |
| `scripts/` | the lanes (`sol-review.sh`, `codex-fix.sh`, `astra-review.sh`, `agy-review.sh`, `review-guard.md`), quota (`codex-quota.sh`, `claude-usage.sh`), sync (`codex-sync.sh`, `codex-trust-hooks.sh`), memory tooling, App Store Connect helper, a deploy-and-verify script | `scripts/README.md` |
| `skills/` | `dev-flow`, `llm-review`, `audit-briefing`, `agent-delegation`, `fix-series`, `multi-session`, `llm-apis` | each `SKILL.md` |
| `codex/` | the Codex delta (`AGENTS.codex.md`), `hooks.template.json`, execpolicy rules, the argument-locked push wrapper, the LaunchAgent template, `local.env.example` | `codex/AGENTS.codex.md` |
| `claude/` | `settings.example.json` (hook wiring, deny list, lane permissions) and `statusline.sh` | — |
| `docs/` | two Claude profiles on one machine | `docs/two-profiles.md` |
| `install.sh` | symlinks the shared parts into `~/.claude`, copies the parts you edit, `--dry-run` first | — |
| `ADOPT.md` | the procedure for letting your own agent analyse this repo and apply what fits — with a paste-ready prompt | itself |

### The hooks

| Hook | Blocks / does |
|---|---|
| `protected-files.sh` | Edit/Write/apply_patch of any basename listed in `~/.claude/protected-files.txt` (e.g. a 120k-line generated file the Edit tool crashes on) |
| `check-secrets-in-llm.sh` | a shell command that sends a secret-looking value to an LLM API host |
| `conventional-commits.sh` | a commit message without a lowercase conventional prefix |
| `changelog-exists.sh` | `git push` from a project without a `CHANGELOG.md` |
| `xcodebuild-lock.sh` | a second `xcodebuild` while one is running |
| `rsync-no-delete.sh` | `rsync --delete` without `--dry-run` first, a delete cap and the receiver-side paths excluded |
| `grok-user-agent.sh` · `gemini-vertex-only.sh` | API-specific traps (a missing User-Agent → Cloudflare 1010; AI Studio outages) |
| `claims-need-evidence.sh` | a commit whose staged ADDED comment/doc lines carry a universal claim with no evidence token |
| `instructions-in-english.sh` | a write that puts Czech prose into an instruction file (two detectors: diacritics, and Czech function words with no English collision — swap them for your language) |
| `precompact-snapshot.sh` · `session-start-compact.sh` · `session-end-uncommitted.sh` | state survives a context compaction; a session end with uncommitted config changes notifies you |

The two hooks that judge file writes read the payload through `hooks/lib/hook-targets.py`, so a
Codex `apply_patch` envelope (which carries no `file_path` at all) is checked file by file exactly
like a Claude `Edit`; the Bash hooks read `tool_input.command`, which both hosts send the same way.

### The lanes

```
sol-review.sh   {plan|review|verify} <repo> <brief> [out]   read-only sandbox, shared guard prompt,
                                                          truncation sentinel, timeout watchdog
codex-fix.sh    [--human-asked] [--astra] <repo> <findings>  writes in ~/.claude/worktrees/<name>,
                                                          installs deps, commits NOTHING; --cleanup
                                                          takes the worktree AND its DerivedData
astra-review.sh --human-asked {plan|review|verify} …       the premium model; refuses without the flag
agy-review.sh   survey <repo> <brief>                       a different training family, corroboration
```

`scripts/review-guard.md` is the one shared reviewer prompt (a ban on reading rationale documents,
"comments are my unverified claims", permission to find nothing); both wrappers refuse to run
without it.

## Install

Requirements: bash 3.2+, `git`, `jq`, `python3`; macOS or Linux. Optional: `codex` (OpenAI Codex
CLI) for the sync and the lanes, the Antigravity CLI for the `agy` optic.

```bash
git clone https://github.com/mikerCZ/one-rulebook ~/.claude/one-rulebook
~/.claude/one-rulebook/install.sh --dry-run      # prints what it would link and copy
~/.claude/one-rulebook/install.sh
```

What it does: symlinks `hooks/`, `scripts/`, `codex/`, `docs/` and each `skills/<name>` into
`~/.claude` (existing non-link entries are left alone and reported), and copies — once, an
existing file is left in place — `CLAUDE.md`, `settings.json` (from `claude/settings.example.json`), `statusline.sh`,
`protected-files.txt`, `instructions-allowed-words.txt` and `codex/local.env` (from the example).
Then: fill in the operator section of `~/.claude/CLAUDE.md`; read `settings.json` — the example
is the author's: auto mode with an empty `ask` list, granting without a prompt `Bash`, `Edit`,
`Write`, web fetch and search, `Task`, notebook edits, process control, the mutating MCP-memory
operations, the Chrome connector and the review/fix lanes — remove every capability you do not
intend to delegate; and on the Codex side run
`~/.claude/scripts/codex-sync.sh --check` followed by `--apply`.

### Or hand it to the agent you already run

You do not have to read this repository yourself. Paste this into your own Claude Code (or Codex)
session, in the home whose `~/.claude` you want to improve:

> Analyse https://github.com/mikerCZ/one-rulebook and apply the patterns that fit my
> configuration. Read its `ADOPT.md` first and follow the procedure there. Before changing
> anything, show me what you would take, what you would skip and why, and ask before anything
> that overwrites a file I already have.

`ADOPT.md` is written for that agent: what to read first, a table of what to take under which
conditions, how to install without clobbering, and — the part that matters — how to prove a hook
fires rather than report that it is configured.

## Two Claude profiles on one machine

`CLAUDE_CONFIG_DIR=~/.claude-bp claude` runs a second login with its own quota. The second
profile shares `CLAUDE.md`, `skills/`, `plugins/` and the auto-memory directory by symlink and keeps
its own `settings.json` and credentials. `docs/two-profiles.md` has the layout, what to share and
what not to, and how `claude-usage.sh` / `statusline.sh` find the right Keychain entry.

## What is deliberately not here

The scope is the collaboration of the agents. The author's platform toolchain (App Store Connect,
Android, simulators, site deploys, disk housekeeping) and the memory-system documentation stay in
the private source — they are about his platforms, not about how the agents work together.
Secrets and credentials, personal data, the author's auto-memory, project-specific records and
private operational procedures are outside this repository too. **Nothing internal about the author,
his company or his apps is meant to be in here**: the incidents that produced the rules live in
private blocks of the source and are stripped on export; what you read is the rule, the mechanism,
and the dated measurements about the tools. If something project-specific escaped that boundary,
open an issue. Several rules refer to four project dashboards by name — `KNOWN_BUGS.md`,
`AUDIT_BACKLOG.md`, `ONDEVICE_TEST_QUEUE.md`, `ROADMAP.md` — a per-project convention (a bug
register, a backlog of deferred audit findings, a queue of checks that need a real device, a
roadmap); adopt the pattern under your own names. Model names (`gpt-5.6-sol`,
`gpt-6-astra`, `claude-fable-5-1`, …) are the ones in use in September 2026 and are overridable
by environment variables in every script that names one.

## Provenance

This repository is a generated export of a private configuration repo. Each export commit names
the source commit's SHA; before an export the tool checks every file against a denylist of the
author's identifiers (app ids, bundle ids, hosts, key ids, …), runs gitleaks and a language scan
over the result, and runs both fixture suites inside it. A denylist is a list, not omniscience —
report anything it missed. Dates in `(verified: …)` and
`(measured …)` are the author's own measurements on their machine on that day — keep them as
what they are, and re-measure before relying on one.

## Contributing

See `CONTRIBUTING.md`. Short version: pull requests are welcome; the maintainer ports them into
the private source and re-exports, so a merged change lands here in an export commit rather than
as your commit. Write comments in English and carry evidence for every universal claim — the
`claims-need-evidence` hook applies to this repo too.

## License

MIT — see `LICENSE`.
