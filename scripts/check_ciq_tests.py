#!/usr/bin/env python3
"""Fail-closed pass/fail gate for the Connect IQ "Run No Evil" test-runner output.

Green ONLY IF, case-insensitively:
  * RAN (RAN_RE)            == the (:test) count in source, AND
  * per-test PASS lines     == that same count, AND
  * the runner's failure count (FAILED_RE) == 0, AND
  * no per-test line matches FAIL_RE.

A pass is NEVER inferred from the mere presence of a "PASSED" token; if no count
signal is parseable at all the gate FAILS (fail-closed). Requiring
`passes == expected` means a genuine failure whose exact wording FAIL_RE happens
to miss is still caught -- a failing test emits no PASS line, so passes < expected
(issue #42 re-review round 2, item 1).

The PASS_RE / FAIL_RE / RAN_RE / FAILED_RE patterns below are broad best-effort
until the DIAGNOSTIC step captures the runner's actual format in sim-run.log, at
which point they are pinned exactly. Because the gate is fail-closed, an
unrecognised format produces a RED result (never a false green) until pinned.

IMPORTANT: every regex is applied PER LINE, never across the whole blob. Python's
`\\s` matches newlines, so a whole-blob search of e.g. `(\\d+)\\s+failures?` would
read "Passed: 41\\nFailed: 0" as "41 failures" -- the count regexes are therefore
run line-by-line so they can never span a line break (#42 re-review round 3).
"""
import pathlib
import re
import sys

log = pathlib.Path(sys.argv[1]).read_text(errors="replace")
src = pathlib.Path("source/PureFunctionTests.mc").read_text()
expected = len(re.findall(r"^\s*\(:test\)", src, re.M))     # == 41 today

PASS_RE = r"\bPASS(?:ED)?\b"
FAIL_RE = r"\b(?:FAIL(?:ED)?|ERROR)\b"
# Count regexes -- matched within a SINGLE line only (see module docstring).
RAN_RE = r"\bRAN\s+(\d+)\s+tests?\b"
FAILED_RE = r"\bfail(?:ure|ed)s?\b\s*[:=]?\s*(\d+)|\b(\d+)\s+fail(?:ure|ed)s?\b"


def is_summary(line):
    """Aggregate/summary lines (RAN N tests, Passed: N, Failed: N, a bare
    PASSED/FAILED, or a separator rule) -- excluded from per-test PASS/FAIL
    counting so they don't inflate `passes` (or make `Failed: 0` look like a
    failing test line)."""
    return bool(
        re.search(r"\bRAN\b", line, re.I)
        or re.search(r"\bpass(?:ed)?\b\s*[:=]", line, re.I)
        or re.search(r"\bfail(?:ure|ed)s?\b\s*[:=]", line, re.I)
        or re.match(r"\s*(?:PASSED|FAILED)\s*$", line, re.I)
        or re.match(r"\s*[=\-*]{4,}\s*$", line)
    )


def first_int(pattern, lines):
    """First integer captured by `pattern` on any single line, else None."""
    for line in lines:
        m = re.search(pattern, line, re.I)
        if m:
            return int(next(g for g in m.groups() if g is not None))
    return None


lines = log.splitlines()
summary = [l for l in lines if is_summary(l)]
per_test = [l for l in lines if not is_summary(l)]

fail_lines = [l for l in per_test if re.search(FAIL_RE, l, re.I)]
pass_lines = [
    l for l in per_test
    if re.search(PASS_RE, l, re.I) and not re.search(FAIL_RE, l, re.I)
]
passes = len(pass_lines)

# RAN count and the runner's own failure count come from SUMMARY lines, matched
# per line so `\s` can never bridge two lines.
ran = first_int(RAN_RE, summary)
if ran is None:
    ran = passes
failed = first_int(FAILED_RE, summary)
if failed is None:
    # No parseable summary failure count -> fall back to counted per-test FAIL
    # lines, but only if we saw ANY per-test verdict at all (else fail-closed).
    failed = len(fail_lines) if (pass_lines or fail_lines) else None

ok = (expected > 0 and ran == expected and passes == expected
      and failed == 0 and not fail_lines)

print(f"expected={expected} ran={ran} passes={passes} "
      f"failed={failed} fail_lines={len(fail_lines)}")
for l in fail_lines:
    print("  >>", l.strip())

if not ok:
    print("::error::CIQ test gate failed "
          "(need ran==passes==expected AND failed==0, case-insensitive).")
    sys.exit(1)
print(f"CIQ test gate OK: {passes}/{expected} passed, 0 failed")
