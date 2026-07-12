#!/usr/bin/env python3
"""Human-readable model-consistency report.

Runs the full assertion catalog and prints a report a coach or sports scientist
can read: the epistemic-status header, hard-invariant failures first, then every
check with its tier, the consensus statement it enforces, and pass/fail/warn.

Usage:
    python run_report.py            # text report to stdout
    python run_report.py --md OUT   # also write a markdown report to OUT
"""
from __future__ import annotations

import argparse
import sys

from fatiguemeter import catalog

HEADER = """\
FatigueMeter — Model-Consistency Report
=======================================
EPISTEMIC STATUS (read first): this harness verifies the app's outputs are
INTERNALLY CONSISTENT WITH THE PROJECT'S STATED MODEL (docs/white-paper.md,
literature-review.md, references.md). That is regression protection, NOT a proof
of agreement with physiological reality. Self-consistency != external validity:
the documents contain synthesis and speculation, so a wrong assumption will be
"certified" here. Only the criterion-validity pilot (white-paper §10) — an
association analysis against a measured external fatigue readout, not this
harness — can establish external validity, and even that is limited by the
absence of an on-bike fatigue ground truth.

TIERS: HARD/ADVERSARIAL/HONESTY/CALIBRATION violations FAIL the build;
PLAUSIBILITY violations are WARNINGS (the science is explicitly uncertain —
ensemble-level directions with wide tolerance, not per-run equalities).
"""

SYMBOL = {"PASS": "PASS", "FAIL": "FAIL", "WARN": "warn", "SKIP": "skip"}


def build_report():
    results = catalog.run_all()
    lines = [HEADER]

    hard_fail = [(c, r) for c, r in results
                 if r.status == "FAIL" and c.tier != "PLAUSIBILITY"]
    lines.append("SUMMARY")
    counts = {}
    for _, r in results:
        counts[r.status] = counts.get(r.status, 0) + 1
    lines.append("  " + "  ".join(f"{k}={counts.get(k,0)}"
                                  for k in ("PASS", "WARN", "SKIP", "FAIL")))
    if hard_fail:
        lines.append("\n!! HARD-INVARIANT / REQUIREMENT FAILURES (top priority) !!")
        for c, r in hard_fail:
            lines.append(f"  [{c.tier}] {c.id} {c.description}\n      -> {r.detail}")
    else:
        lines.append("  No hard-invariant/requirement failures.")

    by_tier = {}
    for c, r in results:
        by_tier.setdefault(c.tier, []).append((c, r))

    for tier in ("HARD", "ADVERSARIAL", "HONESTY", "CALIBRATION", "PLAUSIBILITY"):
        rows = by_tier.get(tier, [])
        if not rows:
            continue
        lines.append(f"\n{tier}")
        for c, r in rows:
            lines.append(f"  [{SYMBOL[r.status]}] {c.id}  {c.description}")
            lines.append(f"        enforces: {c.reference}")
            if r.detail:
                lines.append(f"        observed: {r.detail}")
    return "\n".join(lines) + "\n", hard_fail


def to_markdown():
    results = catalog.run_all()
    out = ["# FatigueMeter — Model-Consistency Report", "", "> " +
           HEADER.replace("\n", "\n> "), "", "| Tier | ID | Check | Status | Observed |",
           "|---|---|---|---|---|"]
    for c, r in results:
        detail = r.detail.replace("|", "\\|")
        out.append(f"| {c.tier} | {c.id} | {c.description} | **{r.status}** | {detail} |")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--md", metavar="OUT", help="also write a markdown report")
    args = ap.parse_args()
    text, hard_fail = build_report()
    print(text)
    if args.md:
        with open(args.md, "w", encoding="utf-8") as fh:
            fh.write(to_markdown())
        print(f"[markdown report written to {args.md}]")
    return 1 if hard_fail else 0


if __name__ == "__main__":
    sys.exit(main())
