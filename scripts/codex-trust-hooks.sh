#!/bin/bash
# Trust the hooks Codex has discovered, without the TUI.
#
# Codex skips an untrusted hooks.json entry IN SILENCE (measured 5.9.2026 on the Mac: a newly added
# hook let its own test case straight through). The only supported ways to trust one are `/hooks`
# in the TUI or the two app-server RPCs the TUI itself uses — `hooks/list` (which returns each
# hook's current hash) and `config/batchWrite` on `hooks.state` (which records it as trusted).
# This script drives those two calls over `codex app-server` on stdio; it computes no hash itself.
#
# Usage:
#   codex-trust-hooks.sh --list            print every discovered hook with its trust status
#   codex-trust-hooks.sh --trust           trust every hook that is untrusted or modified
#   codex-trust-hooks.sh --trust <substr>  trust only hooks whose key contains <substr>
#
# Exit: 0 when nothing is left untrusted after the run, 1 otherwise, 2 on a protocol error.
set -uo pipefail
MODE="${1:---list}"; FILTER="${2:-}"
exec python3 - "$MODE" "$FILTER" "${CODEX_TRUST_CWD:-$HOME}" <<'PY'
import json, os, subprocess, sys, uuid
mode, flt, cwd = sys.argv[1], sys.argv[2], sys.argv[3]
p = subprocess.Popen(["codex", "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=subprocess.DEVNULL, text=True, bufsize=1)
def send(obj):
    p.stdin.write(json.dumps(obj) + "\n"); p.stdin.flush()
def call(method, params):
    rid = str(uuid.uuid4())
    send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
    while True:
        line = p.stdout.readline()
        if not line:
            print(f"app-server closed the pipe during {method}", file=sys.stderr); sys.exit(2)
        msg = json.loads(line)
        if msg.get("id") == rid:
            if "error" in msg:
                print(f"{method} failed: {msg['error']}", file=sys.stderr); sys.exit(2)
            return msg["result"]
call("initialize", {"clientInfo": {"name": "codex-trust-hooks", "version": "1"}})
send({"jsonrpc": "2.0", "method": "initialized"})
res = call("hooks/list", {"cwds": [cwd]})
hooks = [h for e in res["data"] for h in e["hooks"]]
for e in res["data"]:
    for w in e["warnings"]: print(f"  warning: {w}")
    for err in e["errors"]: print(f"  error: {err}")
pending = []
for h in hooks:
    key, st, cur = h.get("key"), h.get("trustStatus"), h.get("currentHash")
    print(f"  {st:9s} {key}")
    if st in ("untrusted", "modified") and (not flt or flt in key):
        pending.append((key, cur))
if mode == "--trust" and pending:
    value = {k: {"trusted_hash": cur} for k, cur in pending}
    call("config/batchWrite", {"edits": [{"keyPath": "hooks.state", "value": value, "mergeStrategy": "upsert"}],
                               "reloadUserConfig": True})
    res = call("hooks/list", {"cwds": [cwd]})
    hooks = [h for e in res["data"] for h in e["hooks"]]
    print("after:")
    for h in hooks: print(f"  {h.get('trustStatus'):9s} {h.get('key')}")
left = [h for h in hooks if h.get("trustStatus") in ("untrusted", "modified")]
send({"jsonrpc": "2.0", "id": "bye", "method": "shutdown", "params": {}}) if False else None
p.stdin.close(); p.terminate()
print(f"{len(hooks)} hook(s), {len(left)} not trusted")
sys.exit(1 if left else 0)
PY
