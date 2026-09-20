# Two Claude Code profiles on one machine

Two subscriptions, one Mac, one rulebook. Claude Code keeps everything about a login under a
configuration directory — `~/.claude` by default — and `CLAUDE_CONFIG_DIR` points a session at a
different one. Each directory is a separate login with its own quota windows, its own
`settings.json` and its own runtime state. What follows is the layout that has run on the
author's machine since 5.9.2026, measured rather than designed.

## Launching

```bash
claude                                      # profile 1: ~/.claude
CLAUDE_CONFIG_DIR=~/.claude-bp claude       # profile 2: ~/.claude-bp
```

Nothing else changes. The second directory is created on first start; `claude login` there logs
the second account in. Any number of sessions can run from either profile at once.

## What the second profile shares, and how

| Entry in `~/.claude-bp` | Kind | Why |
|---|---|---|
| `CLAUDE.md` | symlink → `~/.claude/CLAUDE.md` | one rulebook; an edit reaches both profiles at once |
| `skills` | symlink → `~/.claude/skills` | one set of procedures |
| `plugins` | symlink → `~/.claude/plugins` | one plugin set |
| `projects/<home-slug>/memory` | symlink → the same directory under `~/.claude` | one auto-memory: a lesson learned on either account is seen by both |
| `settings.json` | a **copy**, kept in step by hand | the file must exist per profile; the two differ in `model`, `modelSettings` and `theme` alone (measured 20.9.2026 with `diff`) |
| `.claude.json`, `history.jsonl`, `sessions/`, `file-history/`, `shell-snapshots/`, `telemetry/` | **own** | runtime state and per-account caches; sharing them would mix two logins |
| credentials | **own**, in the Keychain | see below |

`hooks/`, `scripts/` and `statusline.sh` are not present in the second directory at all: the
shared `settings.json` names them by their `~/.claude/…` paths, and the statusline is a command,
so both profiles run the same files.

## Credentials and quota are keyed by the directory

Claude Code stores the login token in the macOS Keychain under a service name that carries a hash
of the configuration directory: `Claude Code-credentials-<first 8 hex of sha256(dir)>`
(verified 5.9.2026: `printf %s /Users/<you>/.claude-bp | shasum -a 256` reproduces the suffix of
the second profile's entry; verified 20.9.2026 with `security find-generic-password -s`: the
default profile's entry is the bare `Claude Code-credentials`, the second one carries the suffix). Two consequences:

- **A usage reading must be made against the right entry.** `scripts/claude-usage.sh` and
  `claude/statusline.sh` compute the service name from `CLAUDE_CONFIG_DIR` and read that
  account's plan windows — the same data `/usage` shows — so a second subscription cannot be read
  against the wrong account.
- **The windows differ, and so do the reset times.** Measured 6.9.2026: profile 1 read 87 % on its
  weekly window resetting 8.9., profile 2 read 91 % resetting 7.9. A lane running on the other
  profile cannot appear in your meter; a jump in yours is yours.

## The shared auto-memory is a shared file system

Because `memory/` is one directory, two live sessions — on the same profile or on different ones —
write into it concurrently. `MEMORY.md` is rewritten whole, so a simultaneous write is
last-writer-wins with no conflict and nothing to notice it. The `multi-session` skill has the
rules; the short form is: read it fresh immediately before writing, write with an explicit path,
grep your own line back afterwards, and check whether the other session already wrote the same
lesson before adding a second file about one incident.

## Codex on the same machine

The Codex side does not know about profiles: `~/.codex` is one directory, and `codex-sync.sh`
generates `~/.codex/AGENTS.md` from the one `~/.claude/CLAUDE.md`. Whichever profile edited the
rulebook, Codex sees the result on the next sync (the LaunchAgent watches the file).
