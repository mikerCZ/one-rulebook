#!/bin/bash
# PreCompact: snapshot volatile state (git branch, status, HEAD) to a file so the
# post-compact session can re-verify what the summary claims instead of trusting it.
# stdin: hook JSON (session_id, cwd, trigger). Cannot influence the summary itself —
# PreCompact stdout goes to the debug log only; the restore side is session-start-compact.sh.
#
# 🔴 It also COPIES THE SESSION SCRATCHPAD, and that half is the one that was missing.
# The git snapshot answers "where is the repo"; it answers nothing about the work — the
# measurements already run, the findings accepted and rejected, the plan drafts, the mutation
# harnesses. Those live in the session scratchpad, which is session-scoped and disappears.
# Measured 6.9.2026 during a long multi-step run: eleven scratchpad artefacts existed that no
# durable copy held, and the only thing standing between them and a compact was the
# author remembering to mirror them. Remembering is not a mechanism.
set -u

input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
trigger=$(printf '%s' "$input" | jq -r '.trigger // "unknown"')
cwd=$(printf '%s' "$input" | jq -r ".cwd // \"$PWD\"")

dir="$HOME/.claude/compact-snapshots"
mkdir -p "$dir"
file="$dir/${session_id}.md"
saved="$dir/${session_id}-scratchpad"

# ── the scratchpad, copied before anything can be summarised away ─────────────────────
# The path is the harness's per-session directory. It is derived, not guessed: the session id is
# the only variable, and a missing directory is reported rather than silently skipped — a hook that
# copies nothing and says nothing is indistinguishable from one that ran.
scratch=""
for base in /private/tmp/claude-501 /tmp/claude-501; do
    [ -d "$base" ] || continue
    hit=$(find "$base" -maxdepth 3 -type d -name scratchpad -path "*${session_id}*" 2>/dev/null | head -1)
    [ -n "$hit" ] && { scratch="$hit"; break; }
done

# ⚠️ Copy the REASONING, not the bulk. Measured 6.9.2026: one day's scratchpad was 69 MB, of which
# ~16 MB was raw build-log directories — the least valuable part, since a build log is
# regenerable and a plan draft is not. Twenty retained sessions at 69 MB is 1.4 GB on a disk that
# had already needed clearing that afternoon. So: skip anything over 1 MB and any *logs* directory,
# and SAY in the snapshot that the skip happened, because a quiet exclusion reads as a full copy.
copied="not attempted"
if [ -n "$scratch" ]; then
    mkdir -p "$saved"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete --max-size=1m \
              --exclude='*logs/' --exclude='*logs-*/' --exclude='*.log' \
              "$scratch"/ "$saved"/ >/dev/null 2>&1 && copied="rsync ok"
    else
        cp -R "$scratch"/. "$saved"/ >/dev/null 2>&1 && copied="cp ok (no rsync: nothing excluded)"
    fi
    n=$(find "$saved" -type f 2>/dev/null | wc -l | tr -d ' ')
    sz=$(du -sh "$saved" 2>/dev/null | cut -f1)
    copied="$copied — $n files, $sz, at $saved (build logs and files >1 MB deliberately skipped)"
else
    copied="NO SCRATCHPAD FOUND for session $session_id (nothing copied)"
fi

{
  echo "# Pre-compact snapshot"
  echo "- taken: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "- trigger: $trigger"
  echo "- cwd: $cwd"
  echo "- scratchpad: $copied"
  if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "- branch: $(git -C "$cwd" branch --show-current 2>/dev/null)"
    echo "- HEAD: $(git -C "$cwd" log -1 --oneline 2>/dev/null)"
    echo "- uncommitted (git status --short, first 50 lines):"
    echo '```'
    git -C "$cwd" status --short 2>/dev/null | head -50
    echo '```'
    echo "- stashes: $(git -C "$cwd" stash list 2>/dev/null | wc -l | tr -d ' ')"
  else
    echo "- git: cwd is not a repository"
  fi
  echo
  echo "⚠️ This file carries the REPO's state and a copy of the scratchpad. It carries nothing that"
  echo "existed only in the conversation — decisions taken, findings rejected and why, numbers"
  echo "already measured. If those matter, they had to be written to a file before now."
} > "$file"

ln -sf "$file" "$dir/latest.md"

# keep the 20 most recent snapshots, and drop scratchpad copies whose snapshot is gone
ls -t "$dir"/*.md 2>/dev/null | grep -v '/latest\.md$' | tail -n +21 | while IFS= read -r old; do
  rm -f "$old"
  rm -rf "${old%.md}-scratchpad"
done

exit 0
