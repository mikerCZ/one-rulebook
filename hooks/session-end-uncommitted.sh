#!/bin/bash
# SessionEnd hook: if ~/.claude has uncommitted changes when a session ends,
# show a macOS notification naming the count.
cd "$HOME/.claude" || exit 0
n=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$n" -gt 0 ]; then
  /usr/bin/osascript -e "display notification \"$n uncommitted change(s) in ~/.claude — commit before you leave\" with title \"Claude Code session ended\"" 2>/dev/null
fi
exit 0
