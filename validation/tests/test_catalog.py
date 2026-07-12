"""Runs the assertion catalog through pytest, enforcing the tier contract:

  HARD / ADVERSARIAL / HONESTY / CALIBRATION  -> must NOT be FAIL (SKIP allowed).
  PLAUSIBILITY                                -> WARN allowed (never fails build);
                                                 emitted as a pytest warning.

A soft-check warning must never fail the build; a hard-invariant violation must
(scientific-validation-prompt.md ground rules).
"""
import warnings

import pytest

from fatiguemeter import catalog


def _ids():
    return [c.id for c in catalog.CATALOG]


@pytest.mark.parametrize("check", catalog.CATALOG, ids=_ids())
def test_check(check):
    result = check.run()
    msg = f"[{check.tier}] {check.id} {check.description} -> {result.status}: {result.detail}"
    if check.tier == "PLAUSIBILITY":
        # soft: WARN is acceptable, only a hard sub-invariant (FAIL) breaks
        if result.status == "WARN":
            warnings.warn(msg)
        assert result.status in ("PASS", "WARN", "SKIP"), msg
    else:
        assert result.status in ("PASS", "SKIP"), msg
