# Contributing

Pull requests and issues are welcome. Two things about this repository are unusual, and both
follow from its first principle, *one writer per target*:

1. **This is a generated export.** The maintainer's private configuration repo is the source;
   each export commit here names that source's SHA (`export from claude-config <sha>`). A merged pull
   request is ported into the source and lands here in the next export commit, attributed in the
   commit body. Do not be surprised that your commit is not the one that appears.
2. **The hooks apply to this repo too.** In particular `hooks/claims-need-evidence.sh`: a comment
   or documentation line that carries a universal claim (the hook's header lists the words it
   greps for) needs its evidence inline — `(verified: <command | file:line | date>)` — or a wording
   that claims nothing. Write comments and documentation in English.

## Before you open a pull request

```bash
CLAUDE_HOME=$PWD hooks/tests/test-hooks.sh          # every hook, both directions
CLAUDE_HOME=$PWD scripts/tests/test-codex-sync.sh   # the sync script against throwaway roots
shellcheck -S warning hooks/*.sh scripts/*.sh       # if you have it
```

A change to a hook needs a case in `hooks/tests/test-hooks.sh` that goes RED without the change
(both directions: the input it must block, and a nearby input it must still allow). A change to
`codex-sync.sh` needs the same in `scripts/tests/test-codex-sync.sh`.

## What is out of scope here

Anything that carries a machine or personal value — an absolute home path, a hostname, a key id, a
GitHub account name in a script. Those belong in `codex/local.env` on each machine; the export tool
refuses to publish a file that still carries one, so a pull request that adds one cannot land.
