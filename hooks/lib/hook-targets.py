#!/usr/bin/env python3
"""Normalise a PreToolUse payload into the files it is about to write.

Two hosts send two different shapes for the same intention, and a hook that reads only one of
them passes the other silently:

  Claude Code   tool_name Edit|Write     tool_input.file_path  + .content / .new_string
  Codex         tool_name apply_patch    tool_input.command    = a "*** Begin Patch" envelope
                (measured 5.9.2026 by logging the hook's own stdin during a real `codex exec`
                 run; the payload carried no file_path at all, which is why the file_path-only
                 version of the protected-files hook returned 0 on a Codex edit)

Codex also reports tool_name "Bash" with tool_input.command for shell calls, so a shell that
carries a patch envelope (apply_patch <<'EOF') is parsed the same way.

Output: one record per target file, as TAB-separated  <path>\t<base64 of the new content>.
Base64 keeps arbitrary content on one line. A delete has empty content.

Patch verbs, taken from the Codex binary's own literals (strings(1) over
/Applications/ChatGPT.app/Contents/Resources/codex, verified 5.9.2026):
    *** Add File: <p>      *** Update File: <p>      *** Delete File: <p>      *** Move to: <p>
"Move to" follows an "Update File" line and renames it, so BOTH names are targets — a rename
into or out of a protected name has to be visible to the caller.
"""
import base64
import json
import os
import re
import sys


def emit(path, content, cwd):
    if not path:
        return
    path = path.strip()
    if not path:
        return
    if not os.path.isabs(path) and cwd:
        path = os.path.normpath(os.path.join(cwd, path))
    print(path + "\t" + base64.b64encode(content.encode("utf-8", "replace")).decode())


def parse_patch(cmd, cwd):
    """Emit (path, added-content) for every file the envelope touches."""
    if "*** Begin Patch" not in cmd:
        return False
    cur, buf, move = None, [], None
    seen = False

    def flush():
        if cur is None:
            return
        body = "".join(buf)
        # A rename writes the new name; the old one is still named by the patch, so report both.
        emit(cur, body if move is None else "", cwd)
        if move is not None:
            emit(move, body, cwd)

    for line in cmd.split("\n"):
        m = re.match(r"^\*\*\* (Add|Update|Delete) File: (.*)$", line)
        if m:
            flush()
            cur, buf, move = m.group(2), [], None
            seen = True
            continue
        m = re.match(r"^\*\*\* Move to: (.*)$", line)
        if m:
            move = m.group(1)
            continue
        if line.startswith("*** End Patch") or line.startswith("*** Begin Patch"):
            continue
        if cur is not None and line.startswith("+"):
            buf.append(line[1:] + "\n")
    flush()
    return seen


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        # A payload we cannot read is not a payload with no targets. Exit 3 so the caller can
        # fall back to a conservative raw match instead of silently allowing the write —
        # observed 5.9.2026: malformed input made the hook return 0, i.e. fail open.
        return 3
    ti = payload.get("tool_input") or {}
    if not isinstance(ti, dict):
        return 3
    cwd = payload.get("cwd") or ""

    fp = ti.get("file_path")
    if fp:
        content = ti.get("content")
        if content is None:
            content = ti.get("new_string")
        emit(fp, content or "", cwd)
        return 0

    cmd = ti.get("command")
    if isinstance(cmd, str) and cmd:
        parse_patch(cmd, cwd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
