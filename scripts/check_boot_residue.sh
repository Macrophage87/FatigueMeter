#!/usr/bin/env bash
# #124 residue-absence gate — prove the FM_TICK boot-smoke heartbeat cannot ship.
#
# The heartbeat is clean BY CONSTRUCTION (the FM_TICK literal lives only in
# source-bootsmoke/, never on the shipping sourcePath), so this is belt-and-
# suspenders mirroring #92's (:test) residue check. It is a BUILT-ARTIFACT scan,
# not a source-text lint (nothing gates (:debug), which is why v1's leak was
# possible). Two checks:
#   1. SOURCE: the `FM_TICK` literal must appear ONLY under source-bootsmoke/
#      (never in source/ or source-bootsmoke-stub/).
#   2. ARTIFACT (if a .prg path is given): grep the built shipping `-d` .prg for
#      the FM_TICK literal -> must be 0. NB we scan the `.prg` (a flat binary
#      whose string pool greps cleanly), NOT the `-e .iq` (a ZIP container that
#      can false-clean while the literal sits compressed inside).
set -euo pipefail
rc=0

echo "== source residue check =="
# Match the STRING LITERAL (`"FM_TICK`) only — the emit is `println("FM_TICK "...)`.
# Doc comments reference the token as `FM_TICK` (backticks), so this ignores prose
# and flags only an actual shippable literal sneaking into a shipping source path.
stray="$(grep -rl -F '"FM_TICK' source source-bootsmoke-stub 2>/dev/null || true)"
if [ -n "$stray" ]; then
  echo "::error::FM_TICK string literal found in a SHIPPING source path (must live only in source-bootsmoke/):"
  echo "$stray"; rc=1
else
  echo "ok: no FM_TICK string literal in source/ or source-bootsmoke-stub/"
fi

for prg in "$@"; do
  echo "== artifact residue check: $prg =="
  if [ ! -f "$prg" ]; then echo "::error::artifact not found: $prg"; rc=1; continue; fi
  n="$(grep -a -c 'FM_TICK' "$prg" 2>/dev/null || true)"
  if [ "${n:-0}" != 0 ]; then
    echo "::error::FM_TICK literal present in shipping artifact $prg ($n hit(s)) — the heartbeat leaked!"; rc=1
  else
    echo "ok: no FM_TICK residue in $prg"
  fi
done

[ "$rc" = 0 ] && echo "boot-smoke residue gate OK" || echo "::error::boot-smoke residue gate FAILED"
exit "$rc"
