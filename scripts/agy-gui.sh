#!/bin/bash
# agy-gui.sh — runs `agy` in the GUI launchd session, where the Keychain is unlocked.
#
# WHY THIS DETOUR EXISTS
# agy keeps its OAuth session in the macOS Keychain (svce "gemini" / "Gemini Safe Storage",
# item <uuid>_refreshToken). A non-interactive SSH session is not allowed into the Keychain —
# `security show-keychain-info` returns "User interaction is not allowed" there — so
# `ssh <mac-host> agy -p ...` demands a NEW
# OAuth login, waits 60 s for a code from the browser and ends with "authentication failed or
# timed out". The session is valid all along.
#
# The launchd domain gui/<uid> belongs to the logged-in console session, where the Keychain
# IS unlocked. Bootstrapping into it works from SSH too — without sudo and without storing a
# password anywhere.
#
# It behaves like `agy`: the arguments pass through unchanged, and stdout, stderr and the exit
# code propagate to the caller.
#
# Usage:
#   agy-gui.sh -p "prompt" --add-dir /repo --mode plan
#   printf '%s\0' -p "prompt" --add-dir /repo | agy-gui.sh --argv-stdin
#
# --argv-stdin reads NUL-separated arguments from stdin. It is the path for calls over SSH:
# the arguments then never reach the command line, so neither the remote shell's quoting nor
# ARG_MAX on a long prompt can break them.
#
# Env: AGY_BIN (default /opt/homebrew/bin/agy), AGY_GUI_TIMEOUT (default 1800 s)

set -uo pipefail

AGY_BIN="${AGY_BIN:-/opt/homebrew/bin/agy}"
TIMEOUT="${AGY_GUI_TIMEOUT:-1800}"

[ -x "$AGY_BIN" ] || { echo "agy-gui: agy not found or not executable: $AGY_BIN" >&2; exit 127; }

# NUL-separated arguments from stdin (see the header).
if [ "${1:-}" = "--argv-stdin" ]; then
    shift
    stdin_args=()
    while IFS= read -r -d '' a; do
        stdin_args+=("$a")
    done
    # bash 3.2 (the system one on macOS): expanding an empty array under `set -u` is an error.
    if [ ${#stdin_args[@]} -gt 0 ]; then
        set -- "${stdin_args[@]}"
    else
        set --
    fi
fi

[ $# -gt 0 ] || { echo "agy-gui: no arguments for agy" >&2; exit 2; }

UIDN="$(id -u)"
LABEL="local.agy-gui.$$"
DIR="$(mktemp -d /tmp/agy-gui.XXXXXX)"
OUT="$DIR/out"; ERR="$DIR/err"; RC="$DIR/rc"; PLIST="$DIR/job.plist"

cleanup() {
    launchctl bootout "gui/$UIDN/$LABEL" 2>/dev/null
    rm -rf "$DIR"
}
trap cleanup EXIT INT TERM

# The plist is assembled in Python (plistlib + shlex.quote), not in the shell — a prompt
# routinely contains quotes, backslashes and XML characters (& < >), and hand-escaping
# would be a silent bomb here.
python3 - "$PLIST" "$LABEL" "$OUT" "$ERR" "$RC" "$HOME" "$AGY_BIN" "$@" <<'PY'
import plistlib, shlex, sys

plist_path, label, out, err, rc, home, agy = sys.argv[1:8]
args = sys.argv[8:]

cmd = " ".join(shlex.quote(x) for x in [agy] + args)
# launchd keeps agy's exit code to itself, so we save it to a file — it doubles as
# the "done" signal that is waited on below.
script = "%s; printf %%s $? > %s" % (cmd, shlex.quote(rc))

with open(plist_path, "wb") as fh:
    plistlib.dump({
        "Label": label,
        "ProgramArguments": ["/bin/sh", "-c", script],
        "RunAtLoad": True,
        "WorkingDirectory": home,
        "StandardOutPath": out,
        "StandardErrorPath": err,
    }, fh)
PY
# The check has to come only here: `|| { … }` spread over two lines after a command
# with a heredoc swallows the second line as the heredoc body.
if [ ! -s "$PLIST" ]; then
    echo "agy-gui: failed to assemble the launchd plist" >&2
    exit 125
fi

launchctl bootout "gui/$UIDN/$LABEL" 2>/dev/null
if ! launchctl bootstrap "gui/$UIDN" "$PLIST" 2>"$DIR/boot.err"; then
    echo "agy-gui: launchctl bootstrap into gui/$UIDN failed" >&2
    sed 's/^/       | /' "$DIR/boot.err" >&2
    echo "       Most common cause: no user is logged in at the console." >&2
    echo "       Check: stat -f%Su /dev/console" >&2
    exit 125
fi

waited=0
while [ ! -s "$RC" ]; do
    sleep 2
    waited=$((waited + 2))
    if [ "$waited" -ge "$TIMEOUT" ]; then
        echo "agy-gui: timeout after ${TIMEOUT}s, run killed" >&2
        [ -s "$OUT" ] && cat "$OUT"
        [ -s "$ERR" ] && cat "$ERR" >&2
        exit 124
    fi
done

[ -s "$OUT" ] && cat "$OUT"
[ -s "$ERR" ] && cat "$ERR" >&2
exit "$(cat "$RC" 2>/dev/null || echo 125)"
