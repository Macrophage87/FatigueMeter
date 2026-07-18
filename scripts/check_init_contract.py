#!/usr/bin/env python3
"""#116 recurrence lint -- ADVISORY (#131). Historically kept FitContributor field
creation on an "init-only" path.

FALSIFIED AXIOM (#130): this lint was built on the contract "`FitContributor.
createField()` is legal ONLY during a DataField's `initialize()`." An on-device
retest (#130, Edge 1050, FW 31.33 / CIQ 6.0.2) proved that FALSE: `createField`
raises the same UNCATCHABLE `System Error: 'Failed invoking '` INSIDE `initialize()`
too -- so R1 mandated the fatal placement and this check was **green on a bricked
build** (passing R1/R2 and bricking became the same fact). It is therefore DEMOTED
to advisory (out of ci-required.needs, #131) and must NOT be treated as a gate for
this crash class. The fault is the createField INVOCATION itself -- uncatchable and
independent of lifecycle phase (both proven on-device) -- but its exact MECHANISM is
still OPEN pending #130's Part B probe: symbol-absent (a resolution/dispatch abort;
likely FitContributor not *effective* in the packaged binary) vs present-but-
misinvoked. The authoritative net is on-device (a lexical check cannot verify a
runtime capability guard or transitive reachability).

R1 will be RE-SCOPED once #130's mechanism is confirmed: from "createField must be
in initialize()" to R1' "a `df has :createField` capability guard must dominate
every createField" (the guard is EXPECTED to be load-bearing -- pending #130 Part B
confirmation). R2 (.createField( confined to FitLogger.mc) is a valid-but-
insufficient code-org rule and stays.

Structured as a small RULE REGISTRY so #114 (method(:hidden) cross-scope, R3) and
the re-scoped R1' can register here rather than shipping N overlapping scripts.

Rules (ADVISORY since #131 -- the job is `continue-on-error`; the script still
exits non-zero so its findings are visible, but it no longer gates merges):
  R1  (#130-FALSIFIED premise -- do NOT act on an R1 finding by "moving to
      initialize()".) In source/FatigueMeterView.mc, `new FitLogger(` appears inside
      the `initialize()` function body. R1 was built on the disproven init-only
      contract; #130 showed createField bricks INSIDE initialize() too, so relocating
      is not the fix -- a `df has :createField` capability guard is (R1', deferred to
      #130's mechanism). Kept only to flag an accidental move onto the compute path
      (which is separately undesirable), NOT to mandate init-only placement.
  R2  `.createField(` may appear ONLY in source/FitLogger.mc. A valid code-org rule
      (single field-creation chokepoint) independent of the R1 phase premise: a
      createField call in another module would be a new, unpinned field-creation
      site. This rule stands.

AST-lite by design: Monkey C class methods are not nested, so a brace/paren
scanner that ignores comments and string literals maps every code occurrence to
its enclosing top-level method deterministically. It canNOT prove full transitive
call-graph reachability or decide hangs -- those uncatchable classes (#115 taxonomy
1-4) are the job of #113's dynamic boot->=1-tick gate. This check owns exactly the
lexical containment invariant, which is sufficient for the #116 class because
`createField` has a single construction chokepoint (`new FitLogger`).
"""
import pathlib
import re
import sys

SRC = pathlib.Path("source")


def code_mask(text):
    """Return a bytearray flag per char: 1 if the char is CODE, 0 if it is inside
    a // line comment, /* block comment */, or "string literal". Lets the brace
    scanner and pattern search ignore braces/keywords that live in prose."""
    mask = bytearray(len(text))
    i, n = 0, len(text)
    LINE, BLOCK, STR, CODE = 1, 2, 3, 0
    state = CODE
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if state == CODE:
            if c == "/" and nxt == "/":
                state = LINE; i += 2; continue
            if c == "/" and nxt == "*":
                state = BLOCK; i += 2; continue
            if c == '"':
                state = STR; mask[i] = 1; i += 1; continue
            mask[i] = 1; i += 1; continue
        if state == LINE:
            if c == "\n":
                state = CODE; mask[i] = 1
            i += 1; continue
        if state == BLOCK:
            if c == "*" and nxt == "/":
                state = CODE; i += 2; continue
            i += 1; continue
        if state == STR:
            if c == "\\":
                i += 2; continue          # skip escaped char (e.g. \")
            if c == '"':
                state = CODE
            i += 1; continue
    return mask


def method_spans(text, mask):
    """Yield (name, body_start, body_end) for every `function <name>(...) { ... }`
    whose keyword is in code. body_start/body_end bracket the {...} body (inclusive
    of the braces). Uses the code mask so dictionary literals, prose braces, and
    string braces inside the body are handled by symmetric brace matching."""
    for m in re.finditer(r"\bfunction\s+(\w+)\s*\(", text):
        if not mask[m.start()]:
            continue
        name = m.group(1)
        # paren-match the parameter list from the '(' we matched.
        p = text.index("(", m.end() - 1)
        depth, j = 0, p
        while j < len(text):
            if mask[j]:
                if text[j] == "(":
                    depth += 1
                elif text[j] == ")":
                    depth -= 1
                    if depth == 0:
                        break
            j += 1
        # first code '{' after the param list is the body open.
        k = j + 1
        while k < len(text) and not (mask[k] and text[k] == "{"):
            k += 1
        if k >= len(text):
            continue
        depth, e = 0, k
        while e < len(text):
            if mask[e]:
                if text[e] == "{":
                    depth += 1
                elif text[e] == "}":
                    depth -= 1
                    if depth == 0:
                        break
            e += 1
        yield name, k, e


def enclosing_method(spans, offset):
    for name, s, e in spans:
        if s <= offset <= e:
            return name
    return None  # class scope / not inside any method


def lineno(text, offset):
    return text[:offset].count("\n") + 1


def rule_r1_fitlogger_init_only(errors):
    """`new FitLogger(` only inside initialize() in FatigueMeterView.mc."""
    f = SRC / "FatigueMeterView.mc"
    if not f.exists():
        print(f"::error::{f}: expected file missing -- cannot verify R1 (#116).")
        errors.append("R1-missing-file")
        return
    text = f.read_text(errors="replace")
    mask = code_mask(text)
    spans = list(method_spans(text, mask))
    hits = [m.start() for m in re.finditer(r"\bnew\s+FitLogger\s*\(", text)
            if mask[m.start()]]
    if not hits:
        print(f"::warning::{f.name}: no `new FitLogger(` found in code -- the FIT "
              f"logger construction site vanished (refactor? verify FitContributor "
              f"fields still register somewhere, guarded by `df has :createField`).")
        errors.append("R1-no-construction")
        return
    for off in hits:
        where = enclosing_method(spans, off)
        ln = lineno(text, off)
        if where == "initialize":
            print(f"ok: {f.name}:{ln}: `new FitLogger(` is inside initialize() "
                  f"(advisory #131; the init-only premise is #130-falsified, so this "
                  f"is informational, not a safety guarantee).")
        else:
            print(f"::warning::{f.name}:{ln}: `new FitLogger(` is inside "
                  f"`{where or '<class scope>'}()`, not initialize(). ADVISORY (#131): "
                  f"the init-only contract is #130-FALSIFIED -- do NOT 'move it back to "
                  f"initialize()' as the fix (createField bricks there too); the real "
                  f"fix is a `df has :createField` capability guard (R1', deferred). "
                  f"This finding only flags an accidental move onto the compute path, "
                  f"which is separately undesirable.")
            errors.append(f"R1:{where}")


def rule_r2_createfield_only_in_fitlogger(errors):
    """`.createField(` only in FitLogger.mc."""
    for f in sorted(SRC.glob("*.mc")):
        text = f.read_text(errors="replace")
        mask = code_mask(text)
        for m in re.finditer(r"\.createField\s*\(", text):
            if not mask[m.start()]:
                continue
            ln = lineno(text, m.start())
            if f.name == "FitLogger.mc":
                continue
            print(f"::error::{f.name}:{ln}: `.createField(` outside FitLogger.mc. "
                  f"FitContributor field creation must live in FitLogger (whose "
                  f"construction R1 pins to initialize()); a createField call in "
                  f"another module is a new field-creation site on an unverified "
                  f"lifecycle phase (#116/#115). Route it through FitLogger or justify.")
            errors.append(f"R2:{f.name}:{ln}")


# Rule registry -- #114 / #115 can append their signature rules here so the whole
# init-contract lint stays one required lane rather than N overlapping scripts.
RULES = [
    rule_r1_fitlogger_init_only,
    rule_r2_createfield_only_in_fitlogger,
]


def main():
    if not SRC.is_dir():
        print("::error::source/ not found -- run from the repo root.")
        return 1
    errors = []
    for rule in RULES:
        rule(errors)
    if errors:
        print(f"::error::init-contract lint (ADVISORY #131) found {len(errors)} "
              f"finding(s) -- see above. NB the init-only premise is #130-falsified; "
              f"R2 (createField confined to FitLogger.mc) is the still-valid rule.")
        return 1
    print("init-contract lint OK (advisory #131): `new FitLogger(` in initialize(); "
          "createField confined to FitLogger.mc (R2). R1's init-only premise is "
          "#130-falsified and awaits the R1' guard-dominance re-scope.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
