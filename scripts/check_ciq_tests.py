#!/usr/bin/env python3
"""Strict pass/fail gate for the CIQ test runner output.
Fails unless: a PASSED summary is present, no FAILED/ERROR lines exist,
and the number of tests RAN equals the number of (:test) functions in source."""
import pathlib, re, sys

log = pathlib.Path(sys.argv[1]).read_text(errors="replace")
src = pathlib.Path("source/PureFunctionTests.mc").read_text()

expected = len(re.findall(r"\(:test\)", src))          # self-updating count
ran_m    = re.search(r"RAN\s+(\d+)\s+tests", log)       # e.g. "PASSED (RAN 23 tests)"
ran      = int(ran_m.group(1)) if ran_m else 0
passed   = re.search(r"\bPASSED\b", log) is not None
bad      = [l for l in log.splitlines() if re.search(r"\b(FAILED|ERROR)\b", l)]

ok = passed and not bad and expected > 0 and ran == expected
print(f"expected={expected} ran={ran} passed={passed} failing_lines={len(bad)}")
for l in bad:
    print("  >>", l)
if not ok:
    print("::error::CIQ test gate failed "
          "(need PASSED, zero FAILED/ERROR, and ran==expected).")
    sys.exit(1)
print("CIQ test gate OK")
