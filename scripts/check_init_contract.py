#!/usr/bin/env python3
"""#116 recurrence lint -- keep FitContributor field creation on the INIT-ONLY path.

Connect IQ contract: `FitContributor.createField()` is legal ONLY during a
DataField's `initialize()`. #108's render-first restructure (#103) deferred
`new FitLogger(self)` -- whose constructor calls `createField()` via
createRecordFields/createSessionFields -> mkRec/mkSes -- into `ensureBuilt()` on
the COMPUTE path, so `createField` ran on tick 1 (out of phase) and raised an
UNCATCHABLE `System Error: 'Failed invoking '` that bypasses every §8.4 try/catch
and bricks the field one frame after the NODATA baseline paints (#116). This is
the precise, deterministic, storage-independent check that would have caught #108
pre-merge -- no simulator, no SDK, no device needed.

This is the #116-specific slice of #115's two-sided init-contract invariant. It is
structured as a small RULE REGISTRY so #114 (method(:hidden) cross-scope) and any
further #115 rules can register here rather than shipping as separate overlapping
scripts.

Rules (both HARD -- exit non-zero on violation):
  R1  In source/FatigueMeterView.mc, `new FitLogger(` must appear ONLY inside the
      `initialize()` function body -- never in `ensureBuilt()`, `computeInner()`,
      or any other method. FitLogger's ctor creates FitContributor fields, so
      constructing it anywhere but initialize() re-ships the #116 brick.
  R2  `.createField(` may appear ONLY in source/FitLogger.mc. FitLogger is the one
      class whose construction R1 pins to initialize(); a createField call in any
      other module would be a new, unpinned field-creation site on an unknown
      lifecycle phase.

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
        print(f"::error::{f.name}: no `new FitLogger(` found in code -- the FIT "
              f"logger construction site vanished; R1 can't confirm it is init-only "
              f"(refactor? verify FitContributor fields still register in initialize()).")
        errors.append("R1-no-construction")
        return
    for off in hits:
        where = enclosing_method(spans, off)
        ln = lineno(text, off)
        if where == "initialize":
            print(f"ok: {f.name}:{ln}: `new FitLogger(` is inside initialize() "
                  f"(FitContributor field creation stays init-only, #116).")
        else:
            print(f"::error::{f.name}:{ln}: `new FitLogger(` is inside "
                  f"`{where or '<class scope>'}()`, NOT initialize(). FitLogger's ctor "
                  f"calls FitContributor.createField(), which is INIT-ONLY -- "
                  f"constructing it on the compute path (e.g. ensureBuilt/computeInner) "
                  f"re-ships the #116 uncatchable System Error brick. Move it back into "
                  f"initialize().")
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
        print(f"::error::init-contract lint FAILED ({len(errors)} violation(s)) -- "
              f"FitContributor field creation must stay on the init-only path (#116).")
        return 1
    print("init-contract lint OK (FitLogger construction is init-only; "
          "createField confined to FitLogger).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
