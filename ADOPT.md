# Adopting one-rulebook with your own agent

You do not have to read this repository yourself. Point the Claude Code (or Codex) session you
already run at it and let it do the reading, the comparison and the wiring — that is what these
tools are for, and the repository was written for an agent reader as much as a human one.

## The prompt

Paste this into your own session, in your own `~/.claude`-bearing home, with the repository URL:

> Analyse https://github.com/mikerCZ/one-rulebook and apply the patterns that fit my
> configuration. Read its `ADOPT.md` first and follow the procedure there. Before changing
> anything, show me what you would take, what you would skip and why, and ask before anything
> that overwrites a file I already have.

Or the short form, if you trust your agent's judgement:

> Analyse the repo https://github.com/mikerCZ/one-rulebook and apply the suitable patterns to
> my configuration.

## The procedure (this is what the agent follows)

1. **Read before touching.** `README.md`, then `CLAUDE.md`, then `scripts/README.md`, then the
   hooks' headers (`hooks/*.sh`, the first 40 lines of each). Do not run anything yet.
2. **Inventory the host.** What exists in `~/.claude` (CLAUDE.md, settings.json, hooks, skills),
   whether `~/.codex` exists, which tools are installed (`jq`, `python3`, `git`, `codex`,
   `gitleaks`), which OS. Every decision below depends on this list.
3. **Classify the repository's content for THIS host**, in a table the operator reads:

   | Category | Take when | Otherwise |
   |---|---|---|
   | The four principles and the red lines of `CLAUDE.md` | in every case — merge them into the operator's CLAUDE.md, keeping their own sections | — |
   | Hooks that need no project (`conventional-commits`, `claims-need-evidence`, `check-secrets-in-llm`, `rsync-no-delete`, `precompact-snapshot`, `session-*`) | the operator commits from Claude Code | skip, say why |
   | `protected-files.sh` | there is a generated or huge file the Edit tool must not touch | skip |
   | `xcodebuild-lock.sh` | Xcode in use (two sessions or agents may build at once) | skip |
   | `instructions-in-english.sh` | the operator writes instructions in a language other than English and wants the instruction layer in English anyway; the detectors are for Czech and need swapping otherwise | skip |
   | `codex-sync.sh` and `codex/` | Codex CLI is installed | skip the Codex side entirely |
   | The review and fix lanes (`sol-review.sh`, `codex-fix.sh`, `astra-review.sh`) | Codex CLI with an OpenAI subscription | skip; the principle (finder ≠ fixer) still applies to whatever reviewer they use |
   | `agy-review.sh`, `agy-*` | Antigravity CLI installed | skip |
   | Process skills (`dev-flow`, `llm-review`, `audit-briefing`, `agent-delegation`, `fix-series`, `multi-session`, `llm-apis`) | in every case — each loads on demand and costs nothing until invoked | — |
   | `docs/two-profiles.md` | more than one Claude subscription | skip |
   | `claude/settings.example.json` | as a REFERENCE for the hook wiring — merge the `hooks` block into the operator's settings; do not replace their permissions | — |

4. **Install by symlink where the operator agrees**, with `install.sh --dry-run` first, so an
   update is a `git pull`. Files the operator edits (CLAUDE.md, settings.json, the lists) are
   copies. An existing file is left in place — merge by hand, show the diff.
5. **Run the fixture suites on the host** (`CLAUDE_HOME=~/.claude hooks/tests/test-hooks.sh` and
   `scripts/tests/test-codex-sync.sh`) and report the counts. A hook that is wired but whose
   suite was not run is a hook nobody has seen fire.
6. **Verify a hook fires**, not that it is configured: stage a commit with `Fix: x` as the message
   and expect `conventional-commits.sh` to block it; try to Edit a file listed in
   `protected-files.txt` and expect a refusal. Report both.
7. **Write the operator's own section** of CLAUDE.md with them (language of replies, who they
   are, their projects and stack) — the repository ships it as a placeholder on purpose.
8. **Say what you did not take and why**, in one list. The operator decides, not the agent.

## What the agent must not do

- Overwrite an existing `CLAUDE.md`, `settings.json` or hook without showing the diff and
  asking. The repository's `install.sh` refuses to; a hand-rolled copy must refuse too.
- Copy the author's identity or preferences into the operator's files: the private blocks of the
  author's rulebook are not in this repository, and every placeholder (`<ssh-host>`, `<bundle-id>`,
  `<key-id>` …) is for the operator's own values.
- Widen permissions. `claude/settings.example.json` is the author's auto-mode configuration; a
  new user starts from their own permissions and adds the hook wiring.
- Present a configured hook as a working one. See step 6.
