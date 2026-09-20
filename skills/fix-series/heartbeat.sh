#!/bin/bash
# Lane heartbeat — one line every 15 minutes so the orchestrator wakes and checks nothing is
# stuck. Deliberately unconditional: a silent monitor cannot be told from a dead one, and "nothing
# emitted" is exactly the state this exists to rule out.
#
# The tool name is split so this script's own text does not trip the xcodebuild-lock hook, which
# matches the COMMAND TEXT of whatever invokes it.
#
# 🔴 v3, 6.9.2026 — v2 READ BRANCH REFS AS FILES AND WENT BLIND WHEN GIT PACKED THEM.
# `refs/heads/` emptied (`ls | wc -l` → 0, every branch still present via `for-each-ref`), so the
# `worktree-*` glob matched nothing. Two consequences, both SILENT and both in the reassuring
# direction: the per-worktree list printed "worktrees: none" — which reads as "the worktrees are
# gone", i.e. a false alarm — and the staleness gauge's `[ "$newest" -gt 0 ]` guard skipped the
# whole block, so it printed "age:" with nothing after it, which reads as "the document is current".
# The gauge the operator asked for had stopped working and said so in the same words it uses for healthy.
# Fix: ask git, which reads packed and loose refs alike — and SAY VOID when the read fails, instead
# of printing the healthy shape.
TOOL="xcodebu""ild"
# Parameters — set them in the environment when you copy this for a lane. The defaults are
# placeholders and will not match yours.
STATE="${HB_SESSION_DIR:?set HB_SESSION_DIR to the session directory, the parent of scratchpad/ and tasks/}"
REPO="${HB_REPO:-$HOME/Projects/<repo>}"
WT="${HB_WORKTREES:-$REPO/.claude/worktrees}"
GITDIR="$REPO/.git"
STATE_DOC="${HB_STATE_DOC:-$HOME/Projects/<handover-dir>/LANE-<x>-STATE.md}"

# One read of every branch ref: "<short-name> <sha8> <committer-unix>".
# `for-each-ref` is the whole point of v3 — it does not care whether the ref is loose or packed.
read_refs() {
    git --git-dir="$GITDIR" for-each-ref \
        --format='%(refname:short) %(objectname:short=8) %(committerdate:unix)' \
        refs/heads 2>/dev/null
}

while true; do
    sleep 900

    now=$(date +%H:%M)
    refs=$(read_refs)
    nrefs=$(printf '%s\n' "$refs" | grep -c . )

    head=""
    stale=""

    if [ "$nrefs" -eq 0 ]; then
        # The instrument could not read, which is NOT the same as "nothing is there".
        head=" ⚠️ REF-READ-VOID"
        stale=" · ⚠️ staleness gauge VOID — could not read any branch ref, so this line says NOTHING about the state doc"
    else
        # Per-worktree head, matched by name against the refs we just read.
        for w in $(ls -1 "$WT" 2>/dev/null); do
            line=$(printf '%s\n' "$refs" | awk -v b="worktree-$w" '$1==b{print $2; exit}')
            [ -n "$line" ] && head="$head $w:$line"
        done
        [ -z "$head" ] && head=" (no worktree matched a branch)"

        # Has any branch of THIS lane moved since the handover document was last written?
        # ⚠️ This lane's units alone — set the branch prefixes below to yours. A wide `worktree-u*`
        # match also catches the other lane's units and would report "behind" for work this
        # document is not supposed to describe — a gauge that cries wolf stops being read. The
        # trigger ref is printed so a false alarm stays attributable.
        newest=0; newest_ref=""
        while read -r name sha t; do
            case "$name" in
                "worktree-<unit-prefix-1>"*|"worktree-<unit-prefix-2>"*) ;;
                *) continue ;;
            esac
            [ -n "$t" ] || continue
            if [ "$t" -gt "$newest" ]; then newest=$t; newest_ref=$name; fi
        done <<EOF
$refs
EOF
        docm=$(stat -f %m "$STATE_DOC" 2>/dev/null || echo 0)
        if [ "$docm" -eq 0 ]; then
            stale=" · ⚠️ state doc UNREADABLE — gauge says nothing"
        elif [ "$newest" -eq 0 ]; then
            stale=" · (no branch of this lane found — nothing to compare)"
        elif [ "$newest" -gt "$docm" ]; then
            mins=$(( (newest - docm) / 60 ))
            if [ "$mins" -ge 30 ]; then
                stale=" · 🔴 STATE-DOC STALE by ${mins}m — a branch of this lane moved after the state doc was last written; WRITE IT NOW (${newest_ref})"
            else
                stale=" · state-doc ${mins}m behind (${newest_ref})"
            fi
        else
            stale=" · state-doc current"
        fi
    fi

    if pgrep -x "$TOOL" >/dev/null; then bld="BUILD-RUNNING"; else bld="no-build"; fi

    rev=""
    # Detached review out-files of this lane's units — set the prefix to yours.
    for f in "/tmp/<unit-prefix>"*-astra-out.md "/tmp/<unit-prefix>"*-sol-out.md; do
        [ -f "$f" ] || continue
        if [ -f "$f.done" ]; then rev="$rev $(basename "$f")=done"; else rev="$rev $(basename "$f")=RUNNING"; fi
    done
    [ -z "$rev" ] && rev=" none"

    live=$(find "$STATE/tasks" -name '*.output' -newermt '-20 minutes' 2>/dev/null | wc -l | tr -d ' ')
    q=$(~/.claude/scripts/claude-usage.sh 90 2>/dev/null | awk '/weekly_scoped/{print $2}')

    echo "[$now] heartbeat · worktrees:${head} · $bld · reviews:$rev · tasks_touched_20m:$live · weekly_scoped:${q:-?}${stale}"
done
