#!/bin/bash
# install.sh — wire this checkout into a Claude Code home, without clobbering what is there.
#
# Two kinds of file, two treatments:
#   LINKED  hooks/, scripts/, codex/, docs/ (every file, keeping subdirectories) and each
#           skills/<name> — one source, updated by `git pull` in this checkout. An existing entry
#           that is NOT a symlink is left alone and reported; an existing symlink that points
#           elsewhere is left alone and reported too.
#   COPIED  the files you are meant to edit — CLAUDE.md, settings.json (from
#           claude/settings.example.json), statusline.sh, protected-files.txt,
#           instructions-allowed-words.txt, codex/local.env (from codex/local.env.example),
#           codex/rules/local.rules (from the example, with __HOME__ rendered). Copied ONCE:
#           an existing file is left in place.
#
# Usage:
#   install.sh [--dry-run] [--claude-home <dir>]     default dir: $CLAUDE_HOME, else ~/.claude
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0; CH="${CLAUDE_HOME:-$HOME/.claude}"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --claude-home) CH="$2"; shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
linked=0; copied=0; kept=0; skipped=0
act() { if [ "$DRY" = 1 ]; then echo "  would $1"; else echo "  $1"; fi; }

link_file() { # link_file <repo-relative path>
  local rel="$1" src="$REPO/$1" dst="$CH/$1"
  if [ -L "$dst" ]; then
    if [ "$(readlink "$dst")" = "$src" ]; then kept=$((kept+1)); return; fi
    echo "  SKIP $rel — a symlink to somewhere else: $(readlink "$dst")"; skipped=$((skipped+1)); return
  fi
  if [ -e "$dst" ]; then echo "  SKIP $rel — exists and is not a symlink (merge by hand)"; skipped=$((skipped+1)); return; fi
  act "link $rel"; [ "$DRY" = 1 ] || { mkdir -p "$(dirname "$dst")" && ln -s "$src" "$dst"; }
  linked=$((linked+1))
}
copy_once() { # copy_once <repo-relative source> <home-relative destination> [render]
  local src="$REPO/$1" dst="$CH/$2"
  if [ -e "$dst" ] || [ -L "$dst" ]; then echo "  KEEP $2 — exists, left as it is"; kept=$((kept+1)); return; fi
  act "copy $1 -> $2"; [ "$DRY" = 1 ] && { copied=$((copied+1)); return; }
  mkdir -p "$(dirname "$dst")"
  if [ "${3:-}" = render ]; then sed "s|__HOME__|$HOME|g" "$src" > "$dst"; else cp -p "$src" "$dst"; fi
  copied=$((copied+1))
}

echo "── one-rulebook install: $REPO -> $CH ──"
[ "$DRY" = 1 ] || mkdir -p "$CH"

for d in hooks scripts codex docs; do
  while IFS= read -r f; do
    case "$f" in codex/local.env.example|codex/rules/local.rules.example) continue ;; esac
    link_file "$f"
  done < <(cd "$REPO" && find "$d" -type f ! -name '.DS_Store' | sort)
done
for s in "$REPO"/skills/*/; do
  [ -d "$s" ] || continue
  link_file "skills/$(basename "$s")"
done

copy_once CLAUDE.md                         CLAUDE.md
copy_once claude/settings.example.json      settings.json
copy_once claude/statusline.sh              statusline.sh
copy_once protected-files.txt               protected-files.txt
copy_once instructions-allowed-words.txt    instructions-allowed-words.txt
copy_once codex/local.env.example           codex/local.env
copy_once codex/rules/local.rules.example   codex/rules/local.rules render
[ "$DRY" = 1 ] || chmod +x "$CH/statusline.sh" 2>/dev/null

echo "── linked $linked · copied $copied · already in place $kept · skipped $skipped ──"
cat <<EOF
Next:
  1. Fill in the operator section at the top of $CH/CLAUDE.md.
  2. Read $CH/settings.json. If it existed before this run it was left untouched — merge the \`hooks\`
     block of claude/settings.example.json into it by hand; the deny list and the lane permissions are examples.
  3. Codex side (optional): $CH/scripts/codex-sync.sh --check, then --apply; on macOS install the
     LaunchAgent: $CH/scripts/codex-sync.sh --render-plist > ~/Library/LaunchAgents/local.one-rulebook.codex-sync.plist
     && launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/local.one-rulebook.codex-sync.plist
  4. Run the fixture suites: CLAUDE_HOME=$CH $CH/hooks/tests/test-hooks.sh ; CLAUDE_HOME=$CH $CH/scripts/tests/test-codex-sync.sh
EOF
if [ "$skipped" -gt 0 ]; then
  echo "Finished with $skipped entry/entries skipped — merge those by hand (see the SKIP lines above)." >&2
  exit 1
fi
exit 0
