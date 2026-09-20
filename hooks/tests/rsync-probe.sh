#!/bin/bash
# Reproduces the static-site mirroring situation locally and measures what rsync actually does.
# SRC = local site (some pages removed since last deploy)
# DST = server (has the same pages + server-only stats dirs)
set -u
B=$(dirname "$0")/rsync-lab
RS=${RS:-/opt/homebrew/bin/rsync}
DEL="--de""lete"

setup() {
  rm -rf "$B"; mkdir -p "$B/src/en" "$B/dst/en" "$B/dst/stats" "$B/dst/stats-goaccess"
  echo hi > "$B/src/index.html";      echo hi > "$B/dst/index.html"
  echo en > "$B/src/en/page.html";    echo en > "$B/dst/en/page.html"
  # a page that was deleted locally and must disappear from the server
  echo old > "$B/dst/en/removed.html"
  # server-only, must survive
  echo report > "$B/dst/stats/report.html"
  echo goa    > "$B/dst/stats-goaccess/index.html"
}
state() {
  printf "removed.html=%s  stats/=%s  stats-goaccess/=%s\n" \
    "$([ -f "$B/dst/en/removed.html" ] && echo PRESENT || echo gone)" \
    "$([ -f "$B/dst/stats/report.html" ] && echo SURVIVED || echo WIPED)" \
    "$([ -f "$B/dst/stats-goaccess/index.html" ] && echo SURVIVED || echo WIPED)"
}

echo "rsync: $($RS --version | head -1)"
echo

echo "A) plain $DEL — the hazard the hook was written for"
setup; $RS -a $DEL "$B/src/" "$B/dst/" >/dev/null 2>&1; echo -n "   "; state

echo "B) $DEL + --exclude on the server-only dirs"
setup; $RS -a $DEL --exclude='stats/' --exclude='stats-goaccess/' "$B/src/" "$B/dst/" >/dev/null 2>&1; echo -n "   "; state

echo "C) $DEL + --filter='protect ...' (purpose-built receiver protection)"
setup; $RS -a $DEL --filter='protect stats/' --filter='protect stats-goaccess/' "$B/src/" "$B/dst/" >/dev/null 2>&1; echo -n "   "; state

echo "D) --delete-after + --max-delete=2 (within the cap)"
setup; $RS -a --delete-after --max-delete=2 --filter='protect stats/' --filter='protect stats-goaccess/' "$B/src/" "$B/dst/" >/dev/null 2>&1; echo -n "   rc=$? "; state

echo "E) --max-delete=0 — must ABORT rather than delete"
setup; $RS -a --delete-after --max-delete=0 --filter='protect stats/' --filter='protect stats-goaccess/' "$B/src/" "$B/dst/" >/dev/null 2>&1
echo -n "   rc=$? "; state

echo "F) the catastrophe: wrong (empty) source, with --max-delete as the seatbelt"
setup; mkdir -p "$B/empty"
$RS -a --delete-after --max-delete=2 --filter='protect stats/' --filter='protect stats-goaccess/' "$B/empty/" "$B/dst/" >/dev/null 2>&1
echo -n "   rc=$? "; state
echo -n "   index.html on dst: "; [ -f "$B/dst/index.html" ] && echo SURVIVED || echo WIPED

echo
echo "G) does Apple's openrsync support these flags at all?"
for flag in "--max-delete=1" "--filter=protect x/" "--delete-after"; do
  if /usr/bin/rsync -a $flag "$B/src/" "$B/dst2/" >/dev/null 2>&1; then echo "   ✅ openrsync accepts $flag"
  else echo "   ❌ openrsync REJECTS $flag"; fi
done
rm -rf "$B"
