"""Rolling 1 Hz ride engine — mirrors PrimitivesCalculator + FatigueMeterView.compute
so the harness can drive whole synthetic/real rides through the ported model and
observe the emitted time series (AFI, F, decoupling, α1, W'bal, ...).

Kept deliberately faithful to the Monkey C compute path (source/*.mc): same
rolling windows, the 5 s DFA budget, the steadiness/stationarity gates, the α1↔F
filter, and the graceful-degradation availability logic.
"""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from typing import List, Optional

import numpy as np

from . import model as M


@dataclass
class RideOutputs:
    afi: List[float] = field(default_factory=list)
    f: List[float] = field(default_factory=list)
    decoup: List[Optional[float]] = field(default_factory=list)
    decoup_avail: List[str] = field(default_factory=list)   # "ok"/"low"/"na"
    alpha1: List[Optional[float]] = field(default_factory=list)
    alpha1_avail: List[str] = field(default_factory=list)
    artifact: List[Optional[float]] = field(default_factory=list)
    wbal_frac: List[float] = field(default_factory=list)
    kj_weighted: List[float] = field(default_factory=list)
    afi_uncertainty: List[float] = field(default_factory=list)
    afi_drift: List[float] = field(default_factory=list)
    prior_dominated: List[bool] = field(default_factory=list)
    cov_pd: List[bool] = field(default_factory=list)
    power_avail: List[bool] = field(default_factory=list)   # power tile live this second
    hr_avail: List[bool] = field(default_factory=list)
    cov_ff: List[float] = field(default_factory=list)       # P[F][F] — for the widening check
    nan_seen: bool = False


def _nonzero_mean(arr):
    a = [v for v in arr if v > 0]
    return sum(a) / len(a) if a else 0.0


def _cv_nonzero(arr):
    a = np.array([v for v in arr if v > 0], dtype=float)
    if a.size < 2:
        return 0.0
    m = a.mean()
    if abs(m) < 1e-6:
        return 0.0
    return float(a.std(ddof=1) / abs(m))


def _coast_frac(arr, ftp):
    if len(arr) == 0:
        return 0.0
    thr = 0.05 * ftp
    return sum(1 for v in arr if v < thr) / len(arr)


class RideEngine:
    """Runs a ride second-by-second. Inputs may be None per-second to simulate a
    dropped sensor (graceful degradation)."""

    EF_BASE_START, EF_BASE_END = 300, 900
    DFA_RECOMPUTE = M.DFA_RECOMPUTE_S

    def __init__(self, cfg: M.Config, seed_f0: float = 0.0):
        self.cfg = cfg
        self.filt = M.AcuteFatigueFilter(cfg)
        self.filt.seed_from_layer3(seed_f0)
        self.power_np = deque(maxlen=30)
        self.win_power = deque(maxlen=600)
        self.win_hr = deque(maxlen=600)
        self.rr_buf = deque(maxlen=400)
        self.ef_baseline: Optional[float] = None
        self.base_sum_ef, self.base_cnt_ef = 0.0, 0
        self.wbal = cfg.wprime
        self.kj_weighted = 0.0
        self.last_dfa = -999
        self.last_rr_time = -9999   # wall-clock staleness timer for RR (§8.4)
        self.cached = (0.0, 0.0, 100.0, 0.0)  # alpha, r2, artifact%, fb

    def _recompute_dfa(self):
        rr = self._trim_rr()
        if len(rr) < 20:
            self.cached = (0.0, 0.0, 100.0, 0.0)
            return
        art = M.artifact_percent(rr, 0.25)
        fb = M.estimate_fb(rr)
        alpha, r2, _ = M.dfa_alpha1(rr, M.DFA_BOX_MIN, M.DFA_BOX_MAX)
        self.cached = (alpha, r2, art, fb)

    def _trim_rr(self):
        allrr = list(self.rr_buf)
        s = 0.0
        start = len(allrr)
        for i in range(len(allrr) - 1, -1, -1):
            s += allrr[i]
            start = i
            if s > M.DFA_WINDOW_S * 1000.0:
                break
        return allrr[start:]

    def _alpha1_metric(self):
        """Returns (value_or_None, availability, artifact%)."""
        alpha, r2, art, fb = self.cached
        if alpha <= 0.0:
            return None, "na", art
        if art > self.cfg.artifact_gate:
            return alpha, "low", art
        cv = _cv_nonzero(self.win_power)
        coast = _coast_frac(self.win_power, self.cfg.ftp)
        if cv > self.cfg.power_cv_gate or coast > self.cfg.coast_frac_gate:
            return alpha, "low", art
        return alpha, "ok", art

    def _decoupling_metric(self, hr_present):
        hr_mean = _nonzero_mean(self.win_hr)
        if hr_mean <= 0:
            return None, "na"
        if self.ef_baseline is None:
            return 0.0, "low"
        np_win = M.normalized_power(list(self.win_power))
        ef_win = M.efficiency_factor(np_win, hr_mean)
        dec = M.decoupling_pct(self.ef_baseline, ef_win)
        cv = _cv_nonzero(self.win_power)
        coast = _coast_frac(self.win_power, self.cfg.ftp)
        if cv > self.cfg.power_cv_gate or coast > self.cfg.coast_frac_gate:
            return dec, "low"
        return dec, "ok"

    def run(self, power, hr, cadence, rr_by_second) -> RideOutputs:
        out = RideOutputs()
        n = len(power)
        for t in range(1, n + 1):
            p = power[t - 1]
            h = hr[t - 1]
            cad = cadence[t - 1] if cadence is not None else None
            rr = rr_by_second[t - 1] if rr_by_second is not None else None

            active = (cad is not None and cad > 0) or (p is not None and p > 0.05 * self.cfg.ftp)
            stationary = (len(self.win_power) >= 30
                          and _cv_nonzero(self.win_power) <= self.cfg.power_cv_gate
                          and _coast_frac(self.win_power, self.cfg.ftp) <= self.cfg.coast_frac_gate)

            # Layer 1 accumulation
            if p is not None and p >= 0:
                self.power_np.append(p)
                self.win_power.append(p)
                self.kj_weighted += M.weight_for_power(p, self.cfg.cp) * p / 1000.0
                self.wbal = M.wprime_bal_step(self.wbal, p, self.cfg.cp, self.cfg.wprime, 1.0)
            else:
                self.win_power.append(0)
            self.win_hr.append(h if (h is not None and h > 0) else 0)

            if self.EF_BASE_START <= t <= self.EF_BASE_END:
                np_now = M.normalized_power(list(self.win_power))
                hr_mean = _nonzero_mean(self.win_hr)
                if np_now > 0 and hr_mean > 0:
                    self.base_sum_ef += np_now / hr_mean
                    self.base_cnt_ef += 1
            if t > self.EF_BASE_END and self.ef_baseline is None and self.base_cnt_ef > 0:
                self.ef_baseline = self.base_sum_ef / self.base_cnt_ef

            if rr:
                for v in rr:
                    if v is not None and 250 < v < 2500:
                        self.rr_buf.append(v)
                        self.last_rr_time = t
            if t - self.last_dfa >= self.DFA_RECOMPUTE:
                self.last_dfa = t
                self._recompute_dfa()
            # §8.4 staleness timer: no fresh RR for RR_STALE_S -> α1 unavailable
            # (don't keep emitting a stale α1 off an aged buffer).
            if t - self.last_rr_time > M.RR_STALE_S:
                self.cached = (0.0, 0.0, 100.0, 0.0)

            a1_val, a1_avail, art = self._alpha1_metric()
            a1_usable = a1_val if a1_avail in ("ok", "low") and a1_val is not None else None
            # α1 update is dropped when unusable (matches metric.isUsable())
            a1_for_filter = a1_usable

            _, _, _, fb = self.cached
            self.filt.step(p, h, a1_for_filter, art, fb, active, stationary)

            dec, dec_avail = self._decoupling_metric(h is not None)
            dec_val = dec if dec_avail in ("ok", "low") and dec is not None else 0.0
            afi = self.filt.afi_blended(dec_val, art)

            out.afi.append(afi)
            out.f.append(self.filt.f_state())
            out.decoup.append(dec)
            out.decoup_avail.append(dec_avail)
            out.alpha1.append(a1_val)
            out.alpha1_avail.append(a1_avail)
            no_rr = self.cached[0] <= 0 and self.cached[2] >= 100
            out.artifact.append(None if no_rr else art)
            out.wbal_frac.append(M.safe_div(self.wbal, self.cfg.wprime, 1.0))
            out.kj_weighted.append(self.kj_weighted)
            out.afi_uncertainty.append(self.filt.afi_uncertainty())
            out.afi_drift.append(self.filt.afi_drift_above_baseline())
            out.prior_dominated.append(self.filt.prior_dominated)
            out.cov_pd.append(self.filt.covariance_is_pd())
            out.power_avail.append(p is not None)
            out.hr_avail.append(h is not None)
            out.cov_ff.append(float(self.filt.P[M.S_F, M.S_F]))
            if not (np.isfinite(afi) and np.isfinite(self.filt.f_state())):
                out.nan_seen = True
        return out
