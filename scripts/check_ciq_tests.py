#!/usr/bin/env python3
"""Fail-closed pass/fail gate for the Connect IQ "Run No Evil" test-runner output.

The runner's format is PINNED from a real PR #43 run. It ends with an
authoritative summary, e.g. a FAILING run:

    Ran 42 tests

    FAILED (passed=39, failed=2, errors=1)

(that historical example predates the #45 fixes; the current suite self-computes
to 105 (:test) functions and runs green 105/105), or a passing run
`PASSED (passed=N, failed=0, errors=0)`, preceded by a RESULTS table whose rows
read `<TestName>   PASS|FAIL|ERROR`.

Green ONLY IF that summary is present AND is `PASSED` AND failed==0 AND errors==0
AND passed==ran==the (:test) count in source AND that count is > 0 AND the run
executed > 0 tests -- so an empty suite that emits `Ran 0 tests / PASSED
(passed=0,...)` can NEVER go green. We trust the runner's own explicit counts
(not a bare `PASSED` token, and not scraped per-test lines, which the runner
prints twice -- once inline, once in the RESULTS table). If the summary is not
parseable at all the gate FAILS (fail-closed), so an unrecognised format is RED,
never a false green.

Note: `ran` counts every (:test) symbol the runner executes across ALL modules,
so a helper wrongly tagged (:test) (e.g. a method that takes arguments) shows up
as an extra ERROR and makes ran != expected -- which the gate correctly reddens.
`expected` counts (:test) across EVERY source/*.mc module (tests live in
PureFunctionTests.mc and CoverageTests.mc), so a test added to any module is
tallied automatically and `ran == expected` stays honest.
"""
import pathlib
import re
import sys

log = pathlib.Path(sys.argv[1]).read_text(errors="replace")
# Count (:test) *test functions* across ALL source modules. Tests live in
# PureFunctionTests.mc and CoverageTests.mc (#14 split the suite so no single
# module exhausts the Monkey C type-checker heap). The runner executes each
# (:test) FUNCTION, so `expected` must tally exactly those.
#
# Match `(:test)` only when it annotates a `function` (#92). `\s+` spans the
# newline, so the canonical `(:test)`-on-its-own-line-then-`function` form still
# counts; a `(:test)` on a `module`/`class` line (as #92 puts on the two test
# modules to strip the whole test surface from release builds) does NOT -- so the
# module tags stay count-neutral. This is also robust to any future non-function
# `(:test)` tag, exactly the mis-tally the docstring above warns about.
expected = sum(
    len(re.findall(r"\(:test\)\s+function\s+\w", f.read_text(errors="replace")))
    for f in sorted(pathlib.Path("source").glob("*.mc"))
)

RAN_RE = r"\bRan\s+(\d+)\s+tests?\b"
SUMMARY_RE = (r"\b(PASSED|FAILED)\b\s*\(\s*passed\s*=\s*(\d+)\s*,"
              r"\s*failed\s*=\s*(\d+)\s*,\s*errors\s*=\s*(\d+)\s*\)")
# RESULTS-table rows that did not pass, for a readable failure list.
FAIL_ROW_RE = r"^\s*(\S+)\s+(FAIL|ERROR)\s*$"

ran_m = re.search(RAN_RE, log, re.I)
sum_m = re.search(SUMMARY_RE, log, re.I)
fail_rows = re.findall(FAIL_ROW_RE, log, re.M)

if not sum_m or not ran_m:
    print(f"expected={expected} "
          f"ran={ran_m.group(1) if ran_m else '?'} "
          f"summary={sum_m.group(0) if sum_m else '?'}")
    print("::error::could not parse the Run No Evil summary "
          "(need 'Ran N tests' and 'PASSED/FAILED (passed=..,failed=..,errors=..)'); "
          "fail-closed.")
    sys.exit(1)

ran = int(ran_m.group(1))
verdict = sum_m.group(1).upper()
passed = int(sum_m.group(2))
failed = int(sum_m.group(3))
errors = int(sum_m.group(4))

ok = (verdict == "PASSED" and failed == 0 and errors == 0
      and expected > 0 and ran > 0          # never green on an empty/zero-test run
      and passed == expected and ran == expected)

print(f"expected={expected} ran={ran} passed={passed} "
      f"failed={failed} errors={errors} verdict={verdict}")
for name, st in fail_rows:
    print(f"  >> {name} {st}")

if not ok:
    print("::error::CIQ test gate failed "
          "(need PASSED with passed==ran==expected, failed==0, errors==0).")
    sys.exit(1)
print(f"CIQ test gate OK: {passed}/{expected} passed, 0 failed, 0 errors")
