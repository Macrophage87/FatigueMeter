#!/usr/bin/env python3
"""#124 boot-smoke verdict — fail-closed parser for a no-`-t` DataField boot.

Styled after check_ciq_tests.py (strict, fail-closed: an absent/empty signal is
FAIL, never GREEN). Consumes the monkeydo stdout log + an optional CIQ_LOG.YML
crash file + the run's exit code, and emits a single PASS/FAIL.

PASS iff ALL hold (any miss => FAIL):
  1. ticks    : count(`FM_TICK`) on stdout >= --min-ticks (K, default 2). K>=2
                proves the tick-1 ensureBuilt() path executed AND the field
                survived past it (a load-fail = 0 ticks; a tick-1 crash = 1).
  2. liveness : ticks >= --min-live (sustained progress to near-timeout). K is
                only a FLOOR -- a crash on tick 3+ still shows >=K ticks, so this
                separate liveness floor is what catches a silent mid-stream crash
                WITHOUT depending on the (channel-selective, per-class-unverified)
                CIQ_LOG.YML crash log. --min-live must be CALIBRATED from AC-1's
                measured Linux tick-rate before promotion to ci-required; it
                defaults conservatively to K for the advisory phase, and the
                measured rate is printed so calibration is data-driven.
  3. exit code: rc in {124, 137} -- a free-running boot is EXPECTED to be
                SIGKILLed by `timeout` (124 = timeout expiry; 137 = 128+SIGKILL).
                rc 0 (a CLEAN EARLY EXIT) is the ANOMALY -- a DataField boot must
                not self-terminate -> FAIL. Any other rc -> FAIL.
  4. no crash : neither stdout NOR the CIQ_LOG.YML file contains a crash marker
                (`System Error` / `Failed invoking` / `app crash`). Both channels
                are scanned (fail-closed superset); which channel actually carries
                each targeted class on Linux is an AC-1 per-class classification
                output (see docs/connectiq-ci-setup.md) -- until that is settled
                the file signal is a HARD requirement, not optional.

Fail-closed: a missing/empty stdout log, or an unparseable rc, is FAIL.
"""
import argparse
import pathlib
import re
import sys

CRASH_RE = re.compile(r"System Error|Failed invoking|app crash", re.I)
TICK_RE = re.compile(r"FM_TICK\b")


def scan(path):
    if not path:
        return None
    p = pathlib.Path(path)
    if not p.is_file():
        return None
    return p.read_text(errors="replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log", help="monkeydo stdout log")
    ap.add_argument("--rc", type=int, required=True, help="run exit code")
    ap.add_argument("--ciqlog", default="", help="CIQ_LOG.YML crash file (may be empty)")
    ap.add_argument("--timeout", type=int, default=30, help="free-run window seconds")
    ap.add_argument("--min-ticks", type=int, default=2, help="K: absolute tick floor")
    ap.add_argument("--min-live", type=int, default=None,
                    help="liveness floor (calibrate from AC-1; defaults to K)")
    a = ap.parse_args()

    min_live = a.min_live if a.min_live is not None else a.min_ticks

    stdout = scan(a.log)
    if stdout is None or stdout.strip() == "":
        print("::error::boot-smoke: stdout log missing/empty — FAIL (fail-closed).")
        print("BOOT-SMOKE: FAIL")
        return 1

    ticks = len(TICK_RE.findall(stdout))
    ciq = scan(a.ciqlog) or ""
    crash_hit = CRASH_RE.search(stdout) or CRASH_RE.search(ciq)

    # rc semantics: timeout-killed = healthy; clean early exit = suspect.
    rc_ok = a.rc in (124, 137)
    clean_early = (a.rc == 0)

    rate = (ticks / a.timeout) if a.timeout > 0 else 0.0
    print(f"boot-smoke: ticks={ticks} over {a.timeout}s (~{rate:.2f} tick/s), "
          f"rc={a.rc}, crash_marker={'YES' if crash_hit else 'no'}")
    print(f"  calibration: set --min-live from this measured rate before promoting "
          f"to ci-required (currently {min_live}).")

    fails = []
    if ticks < a.min_ticks:
        fails.append(f"ticks {ticks} < K={a.min_ticks} (load-fail / tick-1 crash)")
    if ticks < min_live:
        fails.append(f"ticks {ticks} < liveness floor {min_live} (mid-stream crash / no sustain)")
    if clean_early:
        fails.append("rc 0 — clean early exit (a DataField boot must not self-terminate)")
    elif not rc_ok:
        fails.append(f"rc {a.rc} not in {{124,137}} (unexpected termination)")
    if crash_hit:
        fails.append(f"crash marker found: '{crash_hit.group(0)}'")

    if fails:
        for f in fails:
            print(f"::error::boot-smoke: {f}")
        print("BOOT-SMOKE: FAIL")
        return 1
    print("BOOT-SMOKE: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
