#!/usr/bin/env bash
# check_store_fresh.sh -- ADVISORY store-package freshness reminder (#91).
#
# The committed store deliverable `store/FatigueMeter.iq` is a SIGNED binary
# (account-bound developer key) regenerated at release, NOT per-PR -- so CI
# cannot rebuild or byte-compare it. This check is therefore a soft reminder,
# never a gate: it emits a GitHub ::warning:: (no failing status) when tracked
# source has been committed MORE RECENTLY than the store package, i.e. the
# committed `.iq` no longer reflects the source it was built from.
#
# It NEVER exits non-zero on a staleness finding -- staleness on a source PR is
# EXPECTED (you regenerate the package at release, not on every change), so a red
# X here would be pure alarm fatigue. Exits non-zero only on an internal error.
set -euo pipefail

IQ="store/FatigueMeter.iq"
# Source inputs whose change invalidates a previously-built package.
SRC_PATHS=(source resources manifest.xml monkey.jungle)

if [ ! -f "$IQ" ]; then
    echo "::warning::${IQ} is not present -- no committed store package to check."
    exit 0
fi

# Last commit epoch that touched each path set, on the CURRENT checkout.
iq_epoch=$(git log -1 --format=%ct -- "$IQ" 2>/dev/null || echo "")
src_epoch=$(git log -1 --format=%ct -- "${SRC_PATHS[@]}" 2>/dev/null || echo "")

if [ -z "$iq_epoch" ] || [ -z "$src_epoch" ]; then
    # Shallow clone or missing history -- can't judge; stay silent-but-green.
    echo "note: insufficient git history to judge store freshness (need fetch-depth: 0); skipping."
    exit 0
fi

iq_desc=$(git log -1 --format='%h %ci' -- "$IQ" 2>/dev/null || echo "?")
src_desc=$(git log -1 --format='%h %ci' -- "${SRC_PATHS[@]}" 2>/dev/null || echo "?")

if [ "$src_epoch" -gt "$iq_epoch" ]; then
    echo "::warning::store/FatigueMeter.iq is STALE: source (${src_desc}) was committed after the packaged store artifact (${iq_desc}). Regenerate + sign the store package from current main at release -- see docs/release-checklist.md."
    echo "  committed .iq : ${iq_desc}"
    echo "  newest source : ${src_desc}"
else
    echo "store package is fresh: store/FatigueMeter.iq (${iq_desc}) is at or newer than source (${src_desc})."
fi
exit 0
