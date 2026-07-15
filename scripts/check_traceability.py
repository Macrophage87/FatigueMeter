#!/usr/bin/env python3
"""Advisory: every const in Constants.mc must have a row in docs/traceability.md.
Lenient matcher (globs, grouped rows, aliases) so it warns without false alarms."""
import pathlib, re, sys

consts = re.findall(r"\bconst\s+([A-Z][A-Z0-9_]+)\s*=",
                    pathlib.Path("source/Constants.mc").read_text())
doc = pathlib.Path("docs/traceability.md").read_text()

# Rows/symbols struck through as Removed (Rev 5) do not need a live row.
doc_low = doc.lower()
spans = re.findall(r"`([^`]+)`", doc)                 # every backticked code span
frags, globs = set(), set()
for s in spans:
    for tok in re.split(r"[\s/,+()]+", s):
        tok = tok.strip().lower()
        if not tok:
            continue
        (globs if tok.endswith("*") else frags).add(tok)

# Shorthand rows no generic rule can reconstruct -> explicit expansion/alias map.
EXTRA_TRACED = {
    "afi_fresh_max", "afi_building_max", "afi_high_max",     # AFI_FRESH/BUILDING/HIGH_MAX
    "dfa_recompute_s", "dfa_box_min", "dfa_box_max",         # DFA_WINDOW_S / RECOMPUTE_S / BOX_MIN/MAX
    "trimp_female_coeff_default",                            # alias: `trimpFemaleCoeff`
}

def traced(sym: str) -> bool:
    low = sym.lower()
    if low in EXTRA_TRACED or low in doc_low:
        return True
    if any(low.startswith(g[:-1]) for g in globs):          # Q_*, P0_*
        return True
    return any(low == f or low.endswith("_" + f) or low.startswith(f + "_")
               for f in frags)

missing = [c for c in consts if not traced(c)]
print(f"constants={len(consts)} missing_rows={len(missing)}")
for c in missing:
    print("  MISSING:", c)
sys.exit(1 if missing else 0)   # advisory: job is continue-on-error at the workflow level
