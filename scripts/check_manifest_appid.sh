#!/usr/bin/env bash
# Catches the historical placeholder-app-id / store-rejection class, which the
# compile+test path cannot see (a bad id still compiles and still passes tests).
set -euo pipefail
id="$(grep -oiE 'id="[0-9a-f]{32}"' manifest.xml | head -1 | sed -E 's/.*"([0-9a-fA-F]{32})".*/\1/')"
[ -n "$id" ] || { echo "::error::application id missing or not 32-hex"; exit 1; }
case "$id" in
  00000000000000000000000000000000) echo "::error::placeholder (all-zero) app id"; exit 1;;
esac
printf '%s' "$id" | grep -qiE '^(.)\1{31}$' && { echo "::error::placeholder-like app id"; exit 1; }
echo "manifest app id OK: $id"
