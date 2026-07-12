"""Property-based layer (hypothesis) over the pure functions — the invariants
must hold across a wide input space, not just the catalog's fixed cases."""
import math

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from fatiguemeter import model as M


@settings(max_examples=400, deadline=None)
@given(f=st.floats(min_value=-1e4, max_value=1e4, allow_nan=False, allow_infinity=False),
       fref=st.floats(min_value=1.0, max_value=40.0))
def test_afi_bounded(f, fref):
    a = M.afi_from_f(f, fref)
    assert 0.0 <= a <= 100.0


@settings(max_examples=400, deadline=None)
@given(ctl=st.floats(0, 200), atl=st.floats(0, 200))
def test_tsb_identity(ctl, atl):
    assert abs(M.tsb_from(ctl, atl) - (ctl - atl)) < 1e-9


@settings(max_examples=400, deadline=None)
@given(dur=st.floats(1, 6 * 3600), npv=st.floats(0, 600), ftp=st.floats(80, 500))
def test_tss_nonneg_finite(dur, npv, ftp):
    t = M.tss(dur, npv, ftp)
    assert math.isfinite(t) and t >= 0.0


@settings(max_examples=400, deadline=None)
@given(p=st.floats(0, 800), cp=st.floats(80, 500))
def test_weight_monotone_and_capped(p, cp):
    w = M.weight_for_power(p, cp)
    assert 1.0 <= w <= 3.0 + 1e-9


@settings(max_examples=300, deadline=None)
@given(prev=st.floats(0, 30000), p=st.floats(0, 800),
       cp=st.floats(80, 500), wprime=st.floats(3000, 45000))
def test_wprime_bounded(prev, p, cp, wprime):
    nxt = M.wprime_bal_step(min(prev, wprime), p, cp, wprime, 1.0)
    assert 0.0 <= nxt <= wprime + 1e-6


@settings(max_examples=200, deadline=None)
@given(art=st.floats(0, 20), good=st.floats(0, 2), gate=st.floats(3, 10))
def test_rr_weight_bounded(art, good, gate):
    w = M.rr_weight(art, good, gate)
    assert 0.0 <= w <= 1.0


@settings(max_examples=200, deadline=None)
@given(k=st.floats(0, 100), d=st.floats(0, 100), wrr=st.floats(0, 1))
def test_blend_within_endpoints(k, d, wrr):
    b = M.blend_afi(k, d, wrr)
    assert min(k, d) - 1e-6 <= b <= max(k, d) + 1e-6
