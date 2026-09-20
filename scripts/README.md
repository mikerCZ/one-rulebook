# `~/.claude/scripts` — what lives here

The index exists so a fresh session can find a tool instead of writing a second one. Each script's
own header carries the rules and the measurements; this table is only the pointer.

⚠️ A row here says a script EXISTS, not that its defaults still hold. Read the header before use.

## Review and fix lanes

| Script | What it does | Gate |
|---|---|---|
| `sol-review.sh {plan\|review\|verify} <repo> <brief> [out]` | `gpt-5.6-sol` via Codex CLI as a tool-armed reviewer. Read-only sandbox hard-wired, shared guard from `review-guard.md`, timeout watchdog, quota + truncation checks. **The default reviewer.** | none |
| `agy-review.sh {survey\|verify} <repo> <brief> [out]` | Antigravity CLI (Gemini) as a second optic. **Corroboration, not verification** — different training family. | — |
| `astra-review.sh {plan\|review\|verify} <repo> <brief> [out]` | `gpt-6-astra` — the premium reviewer. A thin wrapper over `sol-review.sh`; same guard, `effort=xhigh`. | 🔴 `--human-asked` (flag form; the env form still works but no permission rule matches it) |
| `codex-fix.sh [--human-asked] [--astra] <repo> <findings> [out]` | **The write lane.** Applies findings in an isolated `git worktree` under `~/.claude/worktrees/` with `-s workspace-write`, installs the repo's npm packages first, and hands back an uncommitted diff. Never commits, pushes or merges *(verified 7.9.2026: `grep -nE "git (commit|push|merge)"` over the script returns one line, `:310`, and it is inside the RULES text telling codex not to)*. | `--astra` needs the same claim: `--human-asked` |
| `codex-fix.sh --cleanup <worktree>` | Teardown after the diff was merged or rejected: five safety checks, then the worktree **and its DerivedData** (~5 GB per tree that built, which `git worktree remove` never touches). | refuses a dirty/unmerged tree unless `FIX_CLEANUP_FORCE=1` |
| `review-guard.md` | The shared reviewer prompt (rationale-document ban etc.). Not a script — `sol-review.sh` and `agy-review.sh` both read it, and refuse to run without it. | — |

**Finder and fixer are two runs on purpose.** A reviewer that can write reviews its own patch on the
next pass, and `sol-review.sh`'s prompt forbids running tests *because* its sandbox is read-only.

## Quota and usage

| Script | Answers |
|---|---|
| `codex-quota.sh` | Is there a reason NOT to send a review through the Codex CLI right now? `rc` 0 plenty / 1 low / 2 no reading. ⚠️ Reads the value Codex last logged, not a live one, and cannot see a run you started since. |
| `claude-usage.sh [THRESHOLD]` | The authoritative Claude plan usage — the data `/usage` shows. Profile-aware: reads the account of the `CLAUDE_CONFIG_DIR` it is called from. |

## Housekeeping

| Script | What it does |
|---|---|
| `codex-sync.sh {--check\|--apply} [--tests]` | Keeps the Codex side pointing at this one — regenerates `~/.codex/AGENTS.md` from `CLAUDE.md` + `~/.codex/AGENTS.codex.md`, and re-links the skill and hook symlinks. Run by a LaunchAgent on a source change and hourly. `--check` (alias `--dry-run`) exits 1 on drift and writes `~/.claude/cache/codex-sync-report.json`. Refuses to overwrite a target that lost its generator marker. |
| `codex-trust-hooks.sh [--list\|--trust [substr]]` | Trusts the hooks Codex discovered, without the TUI — drives the same two app-server RPCs `/hooks` uses (`hooks/list` for each hook's current hash, `config/batchWrite` on `hooks.state`). Computes no hash itself. Needed after every hook add/reorder, because an untrusted entry is skipped in silence. |

Both codex scripts run on macOS (LaunchAgent) and on Linux (a systemd path unit + timer instead of the LaunchAgent; measured 12.9.2026 on an Ubuntu host, where `~/.claude` is that machine's own source). Machine-specific values (GitHub owner, projects directory, permission-profile name, LaunchAgent label) live in `codex/local.env` — see `codex/local.env.example`.

## Project tools

| Script | What it does |
|---|---|
| `agy-gui.sh` · `agy-mac` | Run `agy` in a GUI launchd session (unlocked Keychain) / on a remote Mac named by `AGY_MAC_HOST`. |

## Statusline

`~/.claude/statusline.sh` is not in this directory but belongs to the same set: it renders the
three-line footer and reads the logged-in account plus the plan usage of the **current profile**
(`CLAUDE_CONFIG_DIR`), so a second subscription cannot be read against the wrong account.
