#!/usr/bin/env python3
"""#92 recurrence lint -- keep the test surface out of release builds.

Two structural guards so the dead-code leak #92 fixed cannot silently return:

1. (HARD) Every `source/*Tests.mc` module MUST carry a module-level `(:test)`
   annotation, so its ENTIRE contents -- test functions + `Fake*` doubles +
   `near`/`posInf`/`baseStatusCtx` helpers -- are one build-conditional unit that
   the toolchain's built-in `(:test)` auto-exclusion drops from a release build
   (a non---unit-test build strips `(:test)` symbols; `--unit-test` includes them).
   (`excludeAnnotations = test` is deliberately NOT used -- on SDK 9.2.0 it strips
   the `--unit-test` build too, running 0 tests.) A test module that loses the tag
   would leak its un-annotated top-level symbols again. This is the POSITIVE
   residue-absence check: it verifies the mechanism is in place rather than
   trusting a green compile (both release and test builds compile either way).

2. (WARN) Shipping modules (non-`*Tests.mc`) must not gain NEW un-annotated
   test-only seams (`debug*`/`fake*`/`mock*` helpers). The one known, unavoidable
   seam -- `AcuteFatigueFilter.debugInjectNonFiniteState` (it must reach `hidden`
   state, so it lives in the shipping class; it can't be `(:test)` because the
   runner would invoke the 2-arg helper with one logger arg -> arity ERROR; it is
   rendered dead-code-elimination-eligible once its `(:test)` caller is stripped)
   -- is allow-listed below with that rationale.

Exit non-zero only on a guard-1 violation (deterministic, the core invariant).
Guard-2 findings are `::warning::` (a naming heuristic that may false-positive).
"""
import pathlib
import re
import sys

# Known shipping-module test seams that cannot be annotation-stripped, with why.
SEAM_ALLOWLIST = {
    # AcuteFatigueFilter: pokes hidden state x/initialized to reach the §8.4
    # self-heal reset branch; can't be (:test) (arity); DCE-dead in release once
    # its (:test) PureFunctionTests caller is stripped (#42, #92).
    "debugInjectNonFiniteState",
}
SEAM_RE = re.compile(r"^\s*(?:hidden\s+)?(?:static\s+)?function\s+((?:debug|fake|mock)\w*)",
                     re.I | re.M)

errors = 0
warnings = 0
src = pathlib.Path("source")

# Guard 1 (hard): every *Tests.mc is module-level (:test)-annotated.
test_modules = sorted(src.glob("*Tests.mc"))
if not test_modules:
    print("::error::no source/*Tests.mc found -- expected the test suite modules.")
    sys.exit(1)
for f in test_modules:
    t = f.read_text(errors="replace")
    if not re.search(r"\(:test\)\s+module\b", t):
        print(f"::error::{f.name}: test module is not `(:test)`-annotated at module scope "
              f"-- its un-annotated top-level symbols (helpers/fakes) would leak into the "
              f"release image (#92). Add `(:test)` on the line above `module`.")
        errors += 1
    else:
        print(f"ok: {f.name} is module-(:test)-annotated (whole test surface build-conditional)")

# Guard 2 (warn): no NEW un-annotated test seams in shipping modules.
for f in sorted(src.glob("*.mc")):
    if f.name.endswith("Tests.mc"):
        continue
    t = f.read_text(errors="replace")
    for m in SEAM_RE.finditer(t):
        name = m.group(1)
        if name in SEAM_ALLOWLIST:
            continue
        line = t[:m.start()].count("\n") + 1
        print(f"::warning::{f.name}:{line}: `{name}` looks like a test-only seam in a "
              f"shipping module; annotate/relocate it or add it to SEAM_ALLOWLIST with a "
              f"rationale (#92).")
        warnings += 1

if errors:
    print(f"::error::test-surface lint FAILED ({errors} test module(s) missing module-scope "
          f"`(:test)`).")
    sys.exit(1)
print(f"test-surface lint OK (all *Tests.mc module-(:test)-annotated; {warnings} seam warning(s)).")
