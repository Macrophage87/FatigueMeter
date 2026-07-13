"""Faithful Python port of the FatigueMeter pure functions (source/*.mc).

This is the "reimplemented faithfully and cross-checked" path allowed by
docs/prompts/scientific-validation-prompt.md: the app's formulas are ported here
1:1 from the Monkey C so the model-consistency harness can exercise them
off-device. Every function mirrors a `source/*.mc` symbol; the mapping is in the
docstrings and in docs/traceability.md.

EPISTEMIC STATUS: this harness verifies the CODE MATCHES THE PROJECT'S STATED
MODEL (regression protection). It is NOT a proof of agreement with physiological
reality. Self-consistency != external validity (white paper §10).
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import List, Optional, Sequence, Tuple

import numpy as np


# ---------------------------------------------------------------------------
# Constants (mirror source/Constants.mc defaults). Values flagged
# convention/synthesis are also live settings in resources/properties.xml; the
# provenance module cross-checks that the two agree.
# ---------------------------------------------------------------------------
AET_ALPHA1 = 0.75
ANT_ALPHA1 = 0.50
DECOUP_OK = 5.0
DECOUP_CAUTION = 8.0
DECOUP_HIGH = 10.0
KJ_ANCHOR_LOW = 1500.0
KJ_ANCHOR_HIGH = 2500.0
CTL_TAU = 42.0
ATL_TAU = 7.0
TSB_FRESH = 10.0
TSB_OVERREACH = -30.0
TAU_HR = 30.0
TAU_A = 90.0
TAU_REC = 900.0
G_P = 0.45
SIG_A0 = 1.0   # a0/a1 set so the sigmoid midpoint crosses the 0.75 AeT anchor at
SIG_A1 = 0.5   # P_AeT (a0 − a1/2 = 0.75); asymptotes 1.0 (rest) / 0.5 (AnT).
SIG_S = 0.02
KAPPA_I = 0.000145
KAPPA_D = 0.0028
C_F = 0.0167
F_REF = 12.0
Q_HR = 0.5
Q_HRLAT = 0.5
Q_A1 = 0.002
Q_F = 0.05
R_HR = 4.0
R_A1 = 0.0225
P0_HR = 25.0
P0_HRLAT = 25.0
P0_A1 = 0.09
P0_F = 4.0
AFI_FRESH_MAX = 30.0
AFI_BUILDING_MAX = 60.0
AFI_HIGH_MAX = 85.0
WPRIME_MATCH_FRAC = 0.20
TRIMP_MALE_COEFF = 0.64
TRIMP_MALE_EXP = 1.92
TRIMP_FEMALE_COEFF_DEFAULT = 0.86
TRIMP_FEMALE_EXP = 1.67
DFA_WINDOW_S = 120
DFA_RECOMPUTE_S = 5
DFA_BOX_MIN = 4
DFA_BOX_MAX = 16
DFA_R2_GATE = 0.75
DECOUP_REF = 8.0
ARTIFACT_GOOD = 1.0
RR_STALE_S = 10   # after this many seconds without a fresh RR beat, α1 -> unavailable


@dataclass
class Config:
    """Mirrors source/Config.mc — the live settings snapshot with white-paper
    defaults. The harness can also load these from resources/properties.xml to
    assert the code and the shipped defaults agree."""
    ftp: float = 250.0
    cp: float = 240.0
    wprime: float = 20000.0
    hr_max: float = 190.0
    hr_rest: float = 50.0
    sex_female: bool = False
    ctl_seed: float = 70.0
    atl_seed: float = 70.0
    tau_hr: float = TAU_HR
    tau_a: float = TAU_A
    tau_rec: float = TAU_REC
    kappa_i: float = KAPPA_I
    kappa_d: float = KAPPA_D
    c_f: float = C_F
    f_ref: float = F_REF
    a0: float = SIG_A0
    a1: float = SIG_A1
    sigmoid_s: float = SIG_S
    g_p: float = G_P
    q_hr: float = Q_HR
    q_hr_lat: float = Q_HRLAT
    q_a1: float = Q_A1
    q_f: float = Q_F
    r_hr: float = R_HR
    r_a1: float = R_A1
    decoup_ok: float = DECOUP_OK
    decoup_caution: float = DECOUP_CAUTION
    decoup_high: float = DECOUP_HIGH
    artifact_gate: float = 5.0
    power_cv_gate: float = 0.10
    coast_frac_gate: float = 0.10
    kj_anchor: float = 2000.0
    afi_fresh: float = AFI_FRESH_MAX
    afi_building: float = AFI_BUILDING_MAX
    afi_drift_margin: float = 15.0
    decoup_ref: float = DECOUP_REF
    seed_a: float = 0.6
    seed_b: float = 0.4
    seed_tsb_scale: float = 30.0
    feat_w_sev: float = 0.02
    feat_match_w: float = 40.0
    feat_best_w: float = 30.0
    attr_drift_w: float = 100.0
    tsb_fresh: float = TSB_FRESH
    tsb_overreach: float = TSB_OVERREACH
    trimp_female_coeff: float = TRIMP_FEMALE_COEFF_DEFAULT
    acwr_enabled: bool = False
    positive_pilot: bool = False
    ship_number_override: bool = False

    @property
    def p_aet(self) -> float:
        return 0.75 * self.ftp

    def numeric_afi_unlocked(self) -> bool:
        return self.positive_pilot or self.ship_number_override


# ---------------------------------------------------------------------------
# MathUtil (source/MathUtil.mc)
# ---------------------------------------------------------------------------
def clamp(v: float, lo: float, hi: float) -> float:
    if v != v:  # NaN
        return lo
    if v < lo:
        return lo
    if v > hi:
        return hi
    return v


def safe_div(num: float, den: float, fallback: float) -> float:
    if den is None or num is None:
        return fallback
    if -1e-9 < den < 1e-9:
        return fallback
    r = num / den
    if r != r:
        return fallback
    return r


def falling_sigmoid(p, p_aet, a0, a1, s) -> float:
    z = -s * (p - p_aet)
    z = clamp(z, -60.0, 60.0)
    return a0 - a1 / (1.0 + math.exp(z))


def ols_slope_r2(xs, ys) -> Tuple[float, float]:
    n = len(xs)
    if n < 2:
        return 0.0, 0.0
    xs = np.asarray(xs, dtype=float)
    ys = np.asarray(ys, dtype=float)
    sx, sy = xs.sum(), ys.sum()
    sxx, sxy, syy = (xs * xs).sum(), (xs * ys).sum(), (ys * ys).sum()
    denom = n * sxx - sx * sx
    if -1e-12 < denom < 1e-12:
        return 0.0, 0.0
    slope = (n * sxy - sx * sy) / denom
    num = n * sxy - sx * sy
    d2 = (n * sxx - sx * sx) * (n * syy - sy * sy)
    r2 = (num * num) / d2 if d2 > 1e-12 else 0.0
    return slope, clamp(r2, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Layer 1 primitives (source/PrimitivesCalculator.mc, DfaAlpha1.mc)
# ---------------------------------------------------------------------------
def normalized_power(powers: Sequence[float]) -> float:
    if powers is None or len(powers) == 0:
        return 0.0
    p = np.clip(np.asarray(powers, dtype=float), 0.0, None)
    m = np.mean(p ** 4)
    if m <= 0.0:
        return 0.0
    return float(m ** 0.25)


def efficiency_factor(np_val: float, mean_hr: float) -> float:
    return safe_div(np_val, mean_hr, 0.0)


def decoupling_pct(ef_baseline: float, ef_window: float) -> float:
    if ef_baseline is None or ef_baseline <= 1e-6:
        return 0.0
    return (ef_baseline - ef_window) / ef_baseline * 100.0


def weight_for_power(p: float, cp: float) -> float:
    if p <= cp or cp <= 1e-6:
        return 1.0
    frac = (p - cp) / cp
    return 1.0 + clamp(frac, 0.0, 1.0) * 2.0


def wprime_bal_step(w_prev: float, p: float, cp: float, w_prime: float, dt: float) -> float:
    if w_prime <= 1e-6:
        return 0.0
    if p >= cp:
        nxt = w_prev - (p - cp) * dt
    else:
        recovery = (cp - p) * (w_prime - w_prev) / w_prime * dt
        nxt = w_prev + recovery
    return clamp(nxt, 0.0, w_prime)


def dfa_alpha1(rr: Sequence[float], box_min: int = DFA_BOX_MIN,
               box_max: int = DFA_BOX_MAX) -> Tuple[float, float, int]:
    """DFA-α1 (source/DfaAlpha1.mc::compute). Integrate mean-subtracted RR,
    non-overlapping boxes of size n, per-box OLS detrend, RMS residuals -> F(n),
    slope of log F(n) vs log n over n in [box_min, box_max]."""
    rr = np.asarray(rr, dtype=float)
    N = len(rr)
    if N < box_max * 2:
        return 0.0, 0.0, 0
    y = np.cumsum(rr - rr.mean())
    log_n, log_f = [], []
    for n in range(box_min, box_max + 1):
        boxes = N // n
        if boxes < 1:
            break
        sumsq = 0.0
        count = 0
        idx = np.arange(n, dtype=float)
        for b in range(boxes):
            seg = y[b * n:(b + 1) * n]
            # least-squares line fit within the box
            A = np.vstack([idx, np.ones(n)]).T
            slope, intercept = np.linalg.lstsq(A, seg, rcond=None)[0]
            resid = seg - (intercept + slope * idx)
            sumsq += float(np.sum(resid * resid))
            count += n
        if count > 0:
            fn = math.sqrt(sumsq / count)
            if fn > 1e-9:
                log_n.append(math.log(n))
                log_f.append(math.log(fn))
    if len(log_n) < 2:
        return 0.0, 0.0, 0
    slope, r2 = ols_slope_r2(log_n, log_f)
    if slope != slope:
        return 0.0, 0.0, 0
    return slope, r2, len(log_n)


def artifact_percent(rr: Sequence[float], tol_frac: float = 0.25) -> float:
    """Local-median deviation artifact detector (source/DfaAlpha1.mc)."""
    rr = list(rr)
    n = len(rr)
    if n < 5:
        return 100.0
    flagged = 0
    for i in range(n):
        lo = max(0, i - 3)
        hi = min(n - 1, i + 3)
        win = [rr[j] for j in range(lo, hi + 1) if j != i]
        med = float(np.median(win)) if win else 0.0
        if med > 1.0:
            if abs(rr[i] - med) / med > tol_frac:
                flagged += 1
    return 100.0 * flagged / n


def estimate_fb(rr: Sequence[float]) -> float:
    rr = np.asarray(rr, dtype=float)
    n = len(rr)
    if n < 8:
        return 0.0
    total_ms = rr.sum()
    dur_s = total_ms / 1000.0
    if dur_s < 5.0:
        return 0.0
    mean = total_ms / n
    v = rr - mean
    signs = np.where(v >= 0, 1, -1)
    crossings = int(np.sum(signs[1:] != signs[:-1]))
    cycles = crossings / 2.0
    return cycles / dur_s


# ---------------------------------------------------------------------------
# Layer 2 — linear Kalman filter (source/AcuteFatigueFilter.mc, KalmanMath.mc)
# ---------------------------------------------------------------------------
S_HRSS, S_HR, S_A1, S_F = 0, 1, 2, 3


def a1_target(p, p_aet, a0, a1, s) -> float:
    return falling_sigmoid(p, p_aet, a0, a1, s)


def charge_term(p, p_aet, kappa_i, kappa_d, active: bool) -> float:
    intensity = kappa_i * ((p - p_aet) if p > p_aet else 0.0)
    duration = kappa_d if active else 0.0
    return intensity + duration


def afi_from_f(f, f_ref) -> float:
    return 100.0 * clamp(safe_div(f, f_ref, 0.0), 0.0, 1.0)


def afi_from_decoupling(decoup_pct, decoup_ref) -> float:
    return 100.0 * clamp(safe_div(decoup_pct, decoup_ref, 0.0), 0.0, 1.0)


def rr_weight(artifact_pct, artifact_good, artifact_gate) -> float:
    span = artifact_gate - artifact_good
    if span <= 1e-6:
        return 0.0
    return clamp((artifact_gate - artifact_pct) / span, 0.0, 1.0)


def blend_afi(afi_k, afi_d, w_rr) -> float:
    return w_rr * afi_k + (1.0 - w_rr) * afi_d


def fatigue_bucket(f_bpm, f_ref) -> str:
    afi = afi_from_f(f_bpm, f_ref)
    if afi < AFI_FRESH_MAX:
        return "fresh"
    if afi < AFI_BUILDING_MAX:
        return "moderate"
    return "heavy"


def delta_bucket(delta_bpm, f_ref) -> str:
    mag = abs(delta_bpm)
    frac = safe_div(mag, f_ref, 0.0)
    if frac < 0.25:
        return "small"
    if frac < 0.6:
        return "moderate"
    return "large"


def observability_check(A: np.ndarray, h_rows: List[np.ndarray]) -> dict:
    """§4.3a mandatory observability/conditioning check (KalmanMath.mc). Builds
    O = [H; HA; HA^2; HA^3] stacked for every measurement row, returns
    det(O^T O) (>0 ⇔ non-degenerate observability Gramian) and the F-state
    diagonal energy. Numerical recoverability under the model ONLY."""
    O = []
    for h in h_rows:
        r = np.asarray(h, dtype=float).copy()
        O.append(r.copy())
        for _ in range(3):
            r = r @ A
            O.append(r.copy())
    O = np.vstack(O)
    G = O.T @ O
    det = float(np.linalg.det(G))
    f_energy = float(G[S_F, S_F])
    return {"observable": det > 1e-6 and f_energy > 1e-6,
            "det_gram": det, "f_energy": f_energy}


class AcuteFatigueFilter:
    """4-state LINEAR time-varying Kalman filter over [HR_ss, HR, A1, F].
    Faithful port of source/AcuteFatigueFilter.mc + KalmanMath.mc."""

    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.initialized = False
        self.seed_f = 0.0
        self.last_fb = 0.0
        self.fb_seen = False
        self.prior_dominated = True
        self.dominant_rr = False
        self.last_dominant_rr = False
        self.source_switched = False
        self.afi_baseline: Optional[float] = None
        self.afi_base_count = 0
        self.last_afi = 0.0
        self.last_power = 0.0
        self.obs = None
        self.x = np.array([0.0, 0.0, AET_ALPHA1, 0.0])
        self.P = np.zeros((4, 4))

    def seed_from_layer3(self, f0: float):
        self.seed_f = clamp(f0, 0.0, self.cfg.f_ref)

    def _init_state(self, hr, alpha1):
        hr0 = float(hr) if (hr is not None and hr > 0) else (self.cfg.hr_rest + 20.0)
        a10 = alpha1 if (alpha1 is not None and alpha1 > 0) else AET_ALPHA1
        self.x = np.array([self.cfg.hr_rest, hr0, a10, self.seed_f])
        self.P = np.diag([P0_HR, P0_HRLAT, P0_A1, P0_F]).astype(float)
        self.initialized = True
        self._compute_observability()

    def _compute_observability(self):
        c = self.cfg
        dt_hr, dt_a, dt_rec = 1.0 / c.tau_hr, 1.0 / c.tau_a, 1.0 / c.tau_rec
        A = np.zeros((4, 4))
        A[S_HR, S_HRSS] = dt_hr
        A[S_HR, S_HR] = 1.0 - dt_hr
        A[S_HR, S_F] = dt_hr
        A[S_A1, S_A1] = 1.0 - dt_a
        A[S_A1, S_F] = -dt_a * c.c_f
        A[S_F, S_F] = 1.0 - dt_rec
        h_rows = [np.array([0.0, 1.0, 0.0, 0.0]), np.array([0.0, 0.0, 1.0, 0.0])]
        self.obs = observability_check(A, h_rows)

    @staticmethod
    def _symmetrize(P):
        # match KalmanMath.symmetrize: force symmetry + a small positive diagonal
        # floor so P stays conditioned (a genuine divergence otherwise in
        # degenerate cases).
        P = 0.5 * (P + P.T)
        for i in range(4):
            if P[i, i] < 1e-6:
                P[i, i] = 1e-6
        return P

    @staticmethod
    def _predict(x, P, A, u, q_diag):
        x_new = A @ x + u
        P_new = A @ P @ A.T + np.diag(q_diag)
        P_new = AcuteFatigueFilter._symmetrize(P_new)
        return x_new, P_new

    @staticmethod
    def _scalar_update(x, P, H, z, R):
        H = np.asarray(H, dtype=float)
        PHt = P @ H
        S = float(H @ PHt + R)
        if S < 1e-9:
            return x, P
        Hx = float(H @ x)
        innov = z - Hx
        K = PHt / S
        x_new = x + K * innov
        P_new = P - np.outer(K, PHt)
        P_new = AcuteFatigueFilter._symmetrize(P_new)
        return x_new, P_new

    def _effective_r_a1(self, artifact_pct, fb_now):
        c = self.cfg
        r = c.r_a1
        art_factor = 1.0 + 4.0 * clamp(artifact_pct / c.artifact_gate, 0.0, 2.0)
        d_fb = 0.0
        if self.fb_seen:
            d_fb = abs(fb_now - self.last_fb)
        self.fb_seen = True
        fb_factor = 1.0 + 6.0 * clamp(d_fb / 0.1, 0.0, 3.0)
        return r * art_factor * fb_factor * 1.5

    def step(self, power, hr, alpha1, artifact_pct, fb_now, active, stationary):
        """alpha1 is a usable float or None (drop the α1 update)."""
        c = self.cfg
        if not self.initialized:
            self._init_state(hr, alpha1)
        p = float(power) if (power is not None and power >= 0) else self.last_power
        if power is not None and power >= 0:
            self.last_power = float(power)
        self.prior_dominated = stationary

        dt_hr, dt_a, dt_rec = 1.0 / c.tau_hr, 1.0 / c.tau_a, 1.0 / c.tau_rec
        A = np.zeros((4, 4))
        A[S_HR, S_HRSS] = dt_hr
        A[S_HR, S_HR] = 1.0 - dt_hr
        A[S_HR, S_F] = dt_hr
        A[S_A1, S_A1] = 1.0 - dt_a
        A[S_A1, S_F] = -dt_a * c.c_f
        A[S_F, S_F] = 1.0 - dt_rec

        hr_ss_input = c.hr_rest + c.g_p * p
        a1tgt = a1_target(p, c.p_aet, c.a0, c.a1, c.sigmoid_s)
        charge = charge_term(p, c.p_aet, c.kappa_i, c.kappa_d, active)
        u = np.array([hr_ss_input, 0.0, dt_a * a1tgt, charge])
        q_diag = [c.q_hr, c.q_hr_lat, c.q_a1, c.q_f]

        self.x, self.P = self._predict(self.x, self.P, A, u, q_diag)

        if hr is not None and hr > 0:
            self.x, self.P = self._scalar_update(
                self.x, self.P, [0.0, 1.0, 0.0, 0.0], float(hr), c.r_hr)

        if alpha1 is not None:
            r_a1 = self._effective_r_a1(artifact_pct, fb_now)
            self.x, self.P = self._scalar_update(
                self.x, self.P, [0.0, 0.0, 1.0, 0.0], float(alpha1), r_a1)
        self.last_fb = fb_now

        self.x[S_F] = clamp(self.x[S_F], 0.0, 3.0 * c.f_ref)
        self.x[S_A1] = clamp(self.x[S_A1], 0.1, 1.8)

    # --- outputs ---
    def f_state(self) -> float:
        return float(self.x[S_F]) if self.initialized else self.seed_f

    def afi_kalman(self) -> float:
        return afi_from_f(self.f_state(), self.cfg.f_ref)

    def afi_blended(self, decoup_pct, artifact_pct) -> float:
        w_rr = rr_weight(artifact_pct, ARTIFACT_GOOD, self.cfg.artifact_gate)
        afi_k = self.afi_kalman()
        afi_d = afi_from_decoupling(decoup_pct, self.cfg.decoup_ref)
        self.dominant_rr = w_rr >= 0.5
        self.source_switched = self.dominant_rr != self.last_dominant_rr
        self.last_dominant_rr = self.dominant_rr
        afi = blend_afi(afi_k, afi_d, w_rr)
        self.last_afi = afi
        if self.prior_dominated:
            if self.afi_baseline is None:
                self.afi_baseline = afi
            else:
                self.afi_baseline += (afi - self.afi_baseline) / 600.0
            self.afi_base_count += 1
        return afi

    def afi_drift_above_baseline(self) -> float:
        if self.afi_baseline is None or self.afi_base_count < 60:
            return 0.0
        d = self.last_afi - self.afi_baseline
        return d if d > 0 else 0.0

    def afi_uncertainty(self) -> float:
        if not self.initialized:
            return 100.0
        var_f = max(0.0, float(self.P[S_F, S_F]))
        sd = math.sqrt(var_f)
        return clamp(100.0 * sd / self.cfg.f_ref, 0.0, 100.0)

    def covariance_is_pd(self) -> bool:
        # symmetric positive semi-definite check (eigvalues >= -tiny)
        w = np.linalg.eigvalsh(0.5 * (self.P + self.P.T))
        return bool(np.all(w > -1e-6)) and np.all(np.isfinite(self.P))


# ---------------------------------------------------------------------------
# Layer 3 — training-load ledger (source/TrainingLoadLedger.mc)
# ---------------------------------------------------------------------------
def intensity_factor(np_val, ftp) -> float:
    return safe_div(np_val, ftp, 0.0)


def tss(duration_sec, np_val, ftp) -> float:
    iff = intensity_factor(np_val, ftp)
    return (duration_sec / 3600.0) * iff * iff * 100.0


def trimp_increment(hr, hr_rest, hr_max, dt, coeff, expo) -> float:
    span = hr_max - hr_rest
    if span <= 1e-6:
        return 0.0
    hrr = clamp((hr - hr_rest) / span, 0.0, 1.0)
    z = min(60.0, expo * hrr)
    return (dt / 60.0) * hrr * coeff * math.exp(z)


def ewma_fold(prev, load, tau) -> float:
    return prev + (load - prev) / tau


def tsb_from(ctl_y, atl_y) -> float:
    return ctl_y - atl_y


class Ledger:
    """In-memory port of the ledger's day-baseline fold logic (no Storage).
    Used to check same-day idempotency and taper behaviour."""

    def __init__(self, cfg: Config, day: int = 0):
        self.cfg = cfg
        self.ctl_current = cfg.ctl_seed
        self.atl_current = cfg.atl_seed
        self.ctl_day_base = cfg.ctl_seed
        self.atl_day_base = cfg.atl_seed
        self.last_day = day
        self.today_tss = 0.0
        self.ctl_history = [(day, cfg.ctl_seed)]

    def tsb(self) -> float:
        return tsb_from(self.ctl_day_base, self.atl_day_base)

    def advance_day(self, day: int):
        """Simulate crossing to a new calendar day with no training between
        (missed-day decay), matching load()'s decay loop."""
        missed = day - self.last_day
        if 0 < missed < 400:
            for _ in range(missed):
                self.ctl_current = ewma_fold(self.ctl_current, 0.0, CTL_TAU)
                self.atl_current = ewma_fold(self.atl_current, 0.0, ATL_TAU)
            self.ctl_day_base = self.ctl_current
            self.atl_day_base = self.atl_current
            self.last_day = day
            self.today_tss = 0.0

    def finalize_ride(self, load: float, day: int) -> dict:
        # start-of-ride form (CTL_y − ATL_y) is captured BEFORE any new-day
        # rollover, matching TrainingLoadLedger.mc::finalizeRide.
        start_tsb = tsb_from(self.ctl_day_base, self.atl_day_base)
        if day != self.last_day:
            self.ctl_day_base = self.ctl_current
            self.atl_day_base = self.atl_current
            self.last_day = day
            self.today_tss = 0.0
        self.today_tss += load
        ctl_today = ewma_fold(self.ctl_day_base, self.today_tss, CTL_TAU)
        atl_today = ewma_fold(self.atl_day_base, self.today_tss, ATL_TAU)
        self.ctl_current = ctl_today
        self.atl_current = atl_today
        if self.ctl_history and self.ctl_history[-1][0] == day:
            self.ctl_history[-1] = (day, ctl_today)
        else:
            self.ctl_history.append((day, ctl_today))
        return {"ctl_end": ctl_today, "atl_end": atl_today,
                "start_tsb": start_tsb,
                "tsb": tsb_from(ctl_today, atl_today), "load": load}

    def ctl_ramp_per_week(self, today: int) -> Optional[float]:
        if len(self.ctl_history) < 2:
            return None
        target = today - 7
        ref = None
        for d, c in self.ctl_history:
            if d <= target:
                ref = c
        if ref is None:
            return None
        return self.ctl_current - ref


def seed_fatigue_bpm(cfg: Config, tsb_val: float, rmssd_z: float) -> float:
    neg_tsb = max(0.0, -tsb_val)
    neg_z = max(0.0, -rmssd_z)
    frac = clamp(cfg.seed_a * neg_tsb / cfg.seed_tsb_scale + cfg.seed_b * neg_z, 0.0, 0.6)
    return cfg.f_ref * frac


# ---------------------------------------------------------------------------
# Effort characterizer (source/EffortCharacterizer.mc)
# ---------------------------------------------------------------------------
def feat_score(kj_above_cp, severe_seconds, match_depth_sum, be5w, cp,
               w_sev, w_match, w_best) -> float:
    best_bonus = 0.0
    if cp > 1e-6 and be5w > cp:
        best_bonus = (be5w - cp) / cp * w_best
    return kj_above_cp + w_sev * severe_seconds + match_depth_sum * w_match + best_bonus


def attrition_score(attrition_accum, alpha1_drift_below, w_drift) -> float:
    drift_term = alpha1_drift_below * w_drift if alpha1_drift_below > 0 else 0.0
    return attrition_accum + drift_term


def fit_sigmoid(powers: Sequence[float], alphas: Sequence[float]) -> dict:
    """Port of source/CalibrationFit.mc::fitSigmoid — linearised fit of α1 vs P
    with the R²>0.75 acceptance gate; locates the personal AeT (0.75 crossing)."""
    if powers is None or len(powers) < 8:
        return {"accepted": False, "r2": 0.0}
    slope, r2 = ols_slope_r2(powers, alphas)
    mp = float(np.mean(powers))
    ma = float(np.mean(alphas))
    b = ma - slope * mp
    accepted = (r2 > DFA_R2_GATE) and (slope < 0.0)
    p_aet = (AET_ALPHA1 - b) / slope if slope < -1e-9 else 0.0
    s = -4.0 * slope / SIG_A1
    if s < 0.001:
        s = 0.001
    return {"accepted": accepted, "r2": r2, "p_aet": p_aet,
            "slope": slope, "a0": SIG_A0, "a1": SIG_A1, "s": s}


def count_wprime_matches(w_bal_fraction: Sequence[float],
                         thresh: float = WPRIME_MATCH_FRAC) -> Tuple[int, float]:
    """Detect W' matches: fraction drops below thresh then recovers >0.5.
    Returns (count, summed depth). Mirrors EffortCharacterizer.update state machine."""
    in_match = False
    min_frac = 1.0
    count = 0
    depth_sum = 0.0
    for f in w_bal_fraction:
        if not in_match and f < thresh:
            in_match = True
            min_frac = f
        elif in_match:
            min_frac = min(min_frac, f)
            if f > 0.5:
                count += 1
                depth_sum += (thresh - min_frac)
                in_match = False
                min_frac = 1.0
    return count, depth_sum
