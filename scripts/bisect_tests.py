#!/usr/bin/env python3
"""Diagnostic (#9): find which (:test) function in source/PureFunctionTests.mc
crashes the Monkey C 9.2.0 `--unit-test` compiler pass.

The full --unit-test build crashes ("A critical error has occurred", exit 100)
on every device, but compiling with PureFunctionTests.mc removed succeeds. So a
construct in that file trips the compiler's test-instrumentation pass. This
script keeps only the first K test functions (K=1..N), compiles --unit-test each
time, and prints where the crash first appears -- isolating the culprit without
dozens of manual CI round-trips.

Run inside the matco/connectiq-tester container (monkeyc on PATH), with a
developer key already generated at developer_key.der.
"""
import re
import shutil
import subprocess
import sys

PATH = "source/PureFunctionTests.mc"
ORIG = open(PATH).read()
shutil.copy(PATH, "/tmp/orig_tests.mc")

# Split the module into [header, test_block_1, test_block_2, ...]. Each block
# starts at a `(:test)` annotation and runs to the next one; the final block
# also carries the module-closing brace.
marks = [m.start() for m in re.finditer(r"\n[ \t]*\(:test\)", ORIG)]
if not marks:
    print("NO_TESTS_FOUND", flush=True)
    sys.exit(0)

header = ORIG[: marks[0]]
blocks = []
for i, s in enumerate(marks):
    e = marks[i + 1] if i + 1 < len(marks) else len(ORIG)
    blocks.append(ORIG[s:e])
n = len(blocks)
print("NUM_TESTS=%d" % n, flush=True)


def variant(k):
    """File keeping only the first k test functions, module re-closed."""
    if k >= n:
        return ORIG
    return header + "".join(blocks[:k]) + "\n}\n"


def name_of(block):
    m = re.search(r"function\s+(\w+)", block)
    return m.group(1) if m else "?"


first_crash = None
try:
    for k in range(1, n + 1):
        open(PATH, "w").write(variant(k))
        r = subprocess.run(
            ["monkeyc", "-f", "monkey.jungle", "-o", "bin/t.prg",
             "-y", "developer_key.der", "-d", "edge1050", "--unit-test"],
            capture_output=True, text=True,
        )
        ok = r.returncode == 0
        tag = "OK" if ok else "CRASH(exit=%d)" % r.returncode
        print("K=%02d last_added=%-40s -> %s" % (k, name_of(blocks[k - 1]), tag),
              flush=True)
        if not ok and first_crash is None:
            first_crash = (k, name_of(blocks[k - 1]))
finally:
    shutil.copy("/tmp/orig_tests.mc", PATH)

if first_crash:
    print("FIRST_CRASH_AT K=%d test=%s" % first_crash, flush=True)
else:
    print("NO_PREFIX_CRASHED (culprit may be an interaction/aggregate)", flush=True)
