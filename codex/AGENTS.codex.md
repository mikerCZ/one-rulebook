## Codex delta

Everything below this section is the shared rulebook (`~/.claude/CLAUDE.md`), included verbatim so
the two agents cannot drift. This section is the part that is true of Codex and not of Claude.
Where the two disagree, this section wins.

**Where the tooling actually lives.** The helper scripts are in `~/.claude/scripts/` — that is
their real path for both agents, not a Claude-only detail. `~/.codex/scripts` does not exist, and
a reference to it is a broken reference, not a path to create. The permission profile grants read
access to that directory for exactly this reason.

⚠️ **`claude-usage.sh` and `codex-quota.sh` are different instruments, not two names for one.**
`claude-usage.sh` reads the *Claude Code* plan windows from that app's Keychain token; run here it
answers about an account whose quota does not bind this session. The window that binds Codex is
`~/.claude/scripts/codex-quota.sh`. There is no `Codex-usage.sh` and there never was — wherever a
skill gates a long run on remaining quota, that gate is `codex-quota.sh` here.

**Skills.** `~/.agents/skills/*` are symlinks to `~/.claude/skills/*`: one file, one source, no
copy to keep in step. Project skills are read from `<repo>/.agents/skills`; Codex does not look in
`.claude/skills`, so a project skill only exists here if that directory names it.

**Tools that have no counterpart here.** A skill that says "Agent tool", "Task tool" or
"subagent_type" is describing Claude's in-process agents. Codex has no such tool: run the work as a
separate `codex exec`, or hand it back to the operator. The review and fix lanes are plain shell scripts
(`sol-review.sh`, `agy-review.sh`, `astra-review.sh`, `codex-fix.sh`) and behave identically from
either agent.

**Editing.** `apply_patch` is the edit tool, and the `Edit|Write` hook matcher covers it (re-verified 20.9.2026: a real `codex exec` apply_patch on a protected file was refused by `protected-files.sh` while the same run edited an unprotected file). The
protected file (`protected-files.txt`) must still be edited with `sed` or Python through the shell —
the guard now reads patch envelopes and will block a patch that adds, updates, deletes or renames
it (verified 5.9.2026 by a real `codex exec` run that was refused).

**Memory — this is where the shared rulebook does not transfer.** The three layers here are:

| Layer | Where | Loading |
|---|---|---|
| Instructions | this file plus the skills above | always / on demand |
| Codex memories | `~/.codex/memories`, the `memories` feature | Codex's own mechanism |
| MCP memory | the `memory` MCP server | never automatically, `search_nodes()` only |

The "Auto Memory" of the rulebook below is a Claude-side directory of Markdown files; it is not
read here, and writing into it from Codex would put a lesson where this agent will never see it.
Durable lessons learned in a Codex session go into Codex memories, project facts into MCP. The MCP
server is the same `memory.jsonl` file both agents use, so the naming rules below apply unchanged —
including the ban on `read_graph()`.

**Sandbox, approvals and keys.** The default permission profile (named in `codex/local.env`), approval policy
`on-request`, reviewer `auto_review`. `~/.private_keys` and `~/.ssh` are denied outright; that
denial is the protection, never something to route around. Work that has to leave the sandbox goes
through the argument-locked wrappers in `~/.codex/safe-bin` (`safe-branch-push.sh` for `audit/*`
and `codex/*` branches, and any read-only database wrapper installed next to it).

**Hooks.** `~/.codex/hooks/*` are symlinks to `~/.claude/hooks/*`, so both agents run the same
guards from the same files. Codex additionally requires each entry in `hooks.json` to be trusted
before it runs, and an untrusted entry is skipped in silence — measured 5.9.2026: a newly added
hook let its own test case straight through, with nothing in the run's output to say so. After
adding or reordering a hook, confirm it in the Codex startup review, then re-run
`~/.claude/hooks/tests/test-hooks.sh` plus one real edit.

**This file is generated.** Do not edit `~/.codex/AGENTS.md`. Edit this section in
`~/.codex/AGENTS.codex.md`, or the shared rulebook in `~/.claude/CLAUDE.md`, then run
`~/.claude/scripts/codex-sync.sh --apply` (a LaunchAgent does it automatically when either source
changes).

---
