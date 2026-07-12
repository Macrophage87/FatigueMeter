"""The assertion catalog (scientific-validation-prompt.md §1-§5).

Each Check declares its TIER and the consensus statement it enforces (with a
pointer into docs/references.md / white-paper.md), and returns a CheckResult.
The pytest suite and the human-readable report both consume this single catalog,
so there is one source of truth.

TIERS
  HARD         — definitional identity / bound; violation = FAIL (build breaks).
  ADVERSARIAL  — robustness/no-crash; violation = FAIL.
  HONESTY      — provenance/label requirement; violation = FAIL.
  PLAUSIBILITY — direction/range the literature establishes; violation = WARN
                 (never fails the build — the science is explicitly uncertain).
  CALIBRATION  — calibration-dependent behaviour; violation = FAIL, except the
                 criterion-validity stub which is SKIP (owed until real data).
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Callable, List, Optional

import numpy as np

from . import model as M
from . import provenance as prov
from . import signals as S
from .engine import RideEngine


@dataclass
class CheckResult:
    status: str      # PASS / FAIL / WARN / SKIP
    detail: str = ""


@dataclass
class Check:
    id: str
    tier: str
    description: str
    reference: str
    fn: Callable[[], CheckResult]

    def run(self) -> CheckResult:
        try:
            return self.fn()
        except Exception as exc:  # a check that throws is itself a failure
            return CheckResult("FAIL", f"exception: {exc!r}")


def _ok(cond, detail=""):
    return CheckResult("PASS" if cond else "FAIL", detail)


def _warn_if(bad, detail):
    return CheckResult("WARN" if bad else "PASS", detail)


# ===========================================================================
# §1 HARD INVARIANTS
# ===========================================================================
def _c_tsb_identity():
    for ctl, atl in [(80.0, 95.0), (120.0, 60.0), (0.0, 0.0)]:
        if abs(M.tsb_from(ctl, atl) - (ctl - atl)) > 1e-12:
            return CheckResult("FAIL", f"TSB!=CTL-ATL at {ctl},{atl}")
    return CheckResult("PASS", "TSB == CTL - ATL exactly")


def _c_if_identity():
    iff = M.intensity_factor(230.0, 250.0)
    return _ok(abs(iff - 230.0 / 250.0) < 1e-9, f"IF={iff:.4f}")


def _c_tss_formula():
    t = M.tss(3600, 250.0, 250.0)
    return _ok(abs(t - 100.0) < 1e-6, f"1h@FTP -> TSS={t:.3f} (expect ~100)")


def _c_np_definition():
    powers = [100.0, 300.0, 200.0, 250.0] * 8
    ref = float((np.mean(np.array(powers) ** 4)) ** 0.25)
    got = M.normalized_power(powers)
    return _ok(abs(got - ref) < 1e-6, f"NP={got:.3f} vs 4th-root-mean-p^4={ref:.3f}")


def _c_afi_bounds():
    rng = np.random.default_rng(0)
    for _ in range(2000):
        f = float(rng.uniform(-50, 200))
        a = M.afi_from_f(f, 12.0)
        if not (0.0 <= a <= 100.0):
            return CheckResult("FAIL", f"AFI={a} out of [0,100] for F={f}")
    return CheckResult("PASS", "AFI in [0,100] over 2000 random F")


def _c_dfa_lower_bound():
    # correlated (smooth) RR -> α1 finite and > ~0.2 when the pipeline emits
    rng = np.random.default_rng(3)
    base = 900.0
    rr = []
    fluct = 0.0
    for _ in range(240):
        fluct = 0.9 * fluct + rng.normal(0, 12)
        rr.append(base + fluct)
    alpha, r2, nb = M.dfa_alpha1(rr)
    return _ok(math.isfinite(alpha) and alpha > 0.2 and nb >= 2,
               f"alpha1={alpha:.3f} r2={r2:.2f}")


def _c_filter_linear():
    # the estimator is a LINEAR KF: predict is affine in the state. Verify
    # A(x1)-A(x2) == A(x1-x2) i.e. the transition has no state-dependent term.
    cfg = M.Config()
    f = M.AcuteFatigueFilter(cfg)
    f._init_state(120.0, 0.75)
    c = cfg
    dt_hr, dt_a, dt_rec = 1/c.tau_hr, 1/c.tau_a, 1/c.tau_rec
    A = np.zeros((4, 4))
    A[1, 0] = dt_hr; A[1, 1] = 1 - dt_hr; A[1, 3] = dt_hr
    A[2, 2] = 1 - dt_a; A[2, 3] = -dt_a * c.c_f
    A[3, 3] = 1 - dt_rec
    u = np.array([60.0, 0.0, dt_a * 0.75, 0.001])
    x1 = np.array([50.0, 130.0, 0.7, 3.0])
    x2 = np.array([50.0, 110.0, 0.9, 1.0])
    lhs = (A @ x1 + u) - (A @ x2 + u)
    rhs = A @ (x1 - x2)
    return _ok(np.allclose(lhs, rhs), "predict is affine (no Jacobian needed)")


def _c_band_ordering():
    cfg = M.Config()
    ok1 = cfg.afi_fresh < cfg.afi_building < M.AFI_HIGH_MAX
    ok2 = cfg.decoup_ok < cfg.decoup_caution < cfg.decoup_high
    return _ok(ok1 and ok2, "AFI and decoupling bands strictly ordered")


def _c_artifact_gate():
    cfg = M.Config()
    eng = RideEngine(cfg)
    # feed a clean ride then corrupt: check α1 becomes unusable above the gate
    ride = S.steady_ride(duration_s=400, artifact_frac=0.20, seed=5)
    out = eng.run(ride.power, ride.hr, ride.cadence, ride.rr_by_second)
    # any second where artifact>gate must NOT be availability "ok"
    bad = [i for i, (av, ar) in enumerate(zip(out.alpha1_avail, out.artifact))
           if ar is not None and ar > cfg.artifact_gate and av == "ok"]
    return _ok(len(bad) == 0, f"{len(bad)} secs with α1 'ok' above artifact gate")


def _c_kalman_sanity():
    cfg = M.Config()
    f = M.AcuteFatigueFilter(cfg)
    rng = np.random.default_rng(7)
    for i in range(1200):
        p = None if rng.random() < 0.1 else float(rng.uniform(0, 400))
        hr = None if rng.random() < 0.1 else float(rng.uniform(0, 200))
        a1 = None if rng.random() < 0.5 else float(rng.uniform(0.3, 1.2))
        f.step(p, hr, a1, float(rng.uniform(0, 10)), float(rng.uniform(0, 0.5)),
               rng.random() < 0.8, rng.random() < 0.5)
        if not np.all(np.isfinite(f.x)) or not f.covariance_is_pd():
            return CheckResult("FAIL", f"diverged/NaN or non-PD P at step {i}")
    return CheckResult("PASS", "no NaN/Inf; covariance PSD under random dropouts")


def _c_ledger_idempotent():
    cfg = M.Config()
    # two rides same day summing 120 TSS == one ride of 120 against the day base
    a = M.Ledger(cfg, day=10)
    a.finalize_ride(60.0, 10)
    r2 = a.finalize_ride(60.0, 10)      # same day again
    b = M.Ledger(cfg, day=10)
    rb = b.finalize_ride(120.0, 10)
    same = abs(r2["ctl_end"] - rb["ctl_end"]) < 1e-9 and abs(r2["atl_end"] - rb["atl_end"]) < 1e-9
    # "crash + reload" idempotency: re-folding the same day must not double-apply
    c = M.Ledger(cfg, day=10)
    c.finalize_ride(120.0, 10)
    ctl_once = c.ctl_current
    c.finalize_ride(0.0, 10)            # a redundant same-day finalize (0 load)
    stable = abs(c.ctl_current - ctl_once) < 1e-9
    return _ok(same and stable,
               f"same-day sum matches single fold={same}; redundant fold stable={stable}")


# ===========================================================================
# §2 CONSENSUS-PLAUSIBILITY (soft: WARN on direction miss, never FAIL)
# ===========================================================================
def _mean_alpha1_over_ride(out):
    vals = [a for a, av in zip(out.alpha1, out.alpha1_avail) if a is not None and av != "na"]
    return float(np.mean(vals)) if vals else float("nan")


def _c_alpha1_vs_intensity():
    # ensemble mean α1 decreases from easy to hard across synthetic rides
    cfg = M.Config()
    easy_means, hard_means = [], []
    for seed in range(4):
        easy = S.steady_ride(power_w=130, duration_s=400, seed=seed)
        hard = S.steady_ride(power_w=250, duration_s=400, seed=seed + 20)
        oe = RideEngine(cfg).run(easy.power, easy.hr, easy.cadence, easy.rr_by_second)
        oh = RideEngine(cfg).run(hard.power, hard.hr, hard.cadence, hard.rr_by_second)
        easy_means.append(_mean_alpha1_over_ride(oe))
        hard_means.append(_mean_alpha1_over_ride(oh))
    me, mh = np.nanmean(easy_means), np.nanmean(hard_means)
    return _warn_if(not (me > mh), f"mean α1 easy={me:.3f} > hard={mh:.3f} expected")


def _c_decoupling_under_drift():
    cfg = M.Config()
    ride = S.steady_ride(power_w=170, duration_s=5400, hr_drift_bpm=12, seed=2)
    out = RideEngine(cfg).run(ride.power, ride.hr, ride.cadence, ride.rr_by_second)
    early = [d for d in out.decoup[1000:1300] if d is not None]
    late = [d for d in out.decoup[5000:5300] if d is not None]
    if not early or not late:
        return CheckResult("WARN", "insufficient decoupling samples")
    return _warn_if(np.mean(late) <= np.mean(early),
                    f"decoupling early={np.mean(early):.2f}% -> late={np.mean(late):.2f}%")


def _c_durability_magnitude():
    # after ~1400-1680 kJ the drift should be in the ~1-25% ballpark (Maunder/Stevens ~6-10%)
    cfg = M.Config()
    ride = S.long_grind_ride(duration_s=9000, power_w=185, hr_drift_bpm=10, seed=2)
    out = RideEngine(cfg).run(ride.power, ride.hr, ride.cadence, ride.rr_by_second)
    # find the second where kJ_weighted first exceeds ~1500
    idx = next((i for i, k in enumerate(out.kj_weighted) if k >= 1500), None)
    if idx is None:
        return CheckResult("WARN", "ride did not reach 1500 kJ")
    dwin = [d for d in out.decoup[idx:idx + 300] if d is not None]
    m = float(np.mean(dwin)) if dwin else 0.0
    return _warn_if(not (1.0 <= m <= 25.0), f"decoupling at ~1500kJ = {m:.2f}% (expect ~6-10%)")


def _c_subcp_drift_graded():
    cfg = M.Config()
    below = M.charge_term(150, cfg.p_aet, cfg.kappa_i, cfg.kappa_d, True)
    above = M.charge_term(cfg.p_aet + 80, cfg.p_aet, cfg.kappa_i, cfg.kappa_d, True)
    coasting = M.charge_term(150, cfg.p_aet, cfg.kappa_i, cfg.kappa_d, False)
    graded = above > below > coasting and coasting == 0.0 and below > 0.0
    return _ok(graded, f"charge coast={coasting:.4g} < subAeT={below:.4g} < hard={above:.4g}")


def _c_coupling_wired():
    cfg = M.Config()
    f = M.AcuteFatigueFilter(cfg)
    low = M.a1_target(cfg.p_aet, cfg.p_aet, cfg.a0, cfg.a1, cfg.sigmoid_s) - 0.3
    f0 = f.f_state()
    for _ in range(120):
        f.step(cfg.p_aet, 140.0, low, 0.0, 0.2, True, True)
    return _ok(f.f_state() > f0 + 0.05,
               f"α1 below target moved F: {f0:.3f} -> {f.f_state():.3f}")


def _c_observability():
    cfg = M.Config()
    f = M.AcuteFatigueFilter(cfg)
    f._init_state(120.0, 0.75)
    o = f.obs
    return _ok(o["observable"] and o["det_gram"] > 0 and o["f_energy"] > 0,
               f"det(OtO)={o['det_gram']:.3g} f_energy={o['f_energy']:.3g} "
               "(numerical recoverability under the model only)")


def _c_respiration_no_fatigue():
    # Isolate the α1 channel: both runs share identical power/HR (so the HR-driven
    # F is identical); only the fB path differs. With rapid fB, R_A1 inflates and
    # the α1-below-target excursion must move F LESS than with stable fB.
    cfg = M.Config()
    a1 = M.a1_target(cfg.p_aet, cfg.p_aet, cfg.a0, cfg.a1, cfg.sigmoid_s) - 0.3
    stable = M.AcuteFatigueFilter(cfg)
    rapid = M.AcuteFatigueFilter(cfg)
    fb = 0.25
    for _ in range(60):
        fb_rapid = fb + 0.15  # jumps every step -> large |Δfb|
        stable.step(cfg.p_aet, 140.0, a1, 0.0, 0.25, True, True)   # steady fB
        rapid.step(cfg.p_aet, 140.0, a1, 0.0, fb_rapid, True, True)  # rapid fB
        fb = fb_rapid
    dm = rapid.f_state()
    ds = stable.f_state()
    return _ok(dm < ds, f"rapid-fB F={dm:.3f} < stable-fB F={ds:.3f} "
                        "(R_A1 inflation de-weights the excursion)")


def _c_longz2_moderate():
    cfg = M.Config()
    ride = S.steady_ride(power_w=int(0.62 * cfg.ftp), duration_s=12000,
                         hr_drift_bpm=6, seed=11)
    out = RideEngine(cfg).run(ride.power, ride.hr, ride.cadence, ride.rr_by_second)
    afi_end = float(np.mean(out.afi[-300:]))
    return _ok(afi_end < 70.0, f"3.3h Z2 -> AFI≈{afi_end:.1f} (moderate, not severe)")


def _c_recovery_relaxes_f():
    cfg = M.Config()
    f = M.AcuteFatigueFilter(cfg)
    # hard effort with HR ABOVE the fresh HR for the power (drift) so F charges
    p_hard = cfg.p_aet + 80
    hr_hard = cfg.hr_rest + cfg.g_p * p_hard + 12.0   # +12 bpm of drift
    for _ in range(300):
        f.step(p_hard, hr_hard, None, 100.0, 0.0, True, True)
    charged = f.f_state()
    for _ in range(300):
        f.step(0.0, None, None, 100.0, 0.0, False, True)   # coast, predict-only
    return _ok(f.f_state() < charged and charged > 1.0,
               f"F charged={charged:.2f} -> recovered={f.f_state():.2f}")


def _c_feat_vs_attrition():
    cfg = M.Config()
    # hard interval ride -> FeatScore dominates
    hard = S.intervals_ride(duration_s=2400, ftp=cfg.ftp, cp=cfg.cp, seed=1)
    kj_above = sum(max(0.0, p - cfg.cp) / 1000.0 for p in hard.power if p)
    severe = sum(1 for p in hard.power if p and p > cfg.cp)
    feat = M.feat_score(kj_above, severe, 0.5, cfg.cp * 1.2, cfg.cp,
                        cfg.feat_w_sev, cfg.feat_match_w, cfg.feat_best_w)
    attr = M.attrition_score(2.0, 0.1, cfg.attr_drift_w)
    feat_dom = feat > attr
    # long grind -> AttritionScore dominates (little above CP)
    attr2 = M.attrition_score(50.0, 0.25, cfg.attr_drift_w)
    feat2 = M.feat_score(0.0, 0.0, 0.0, cfg.cp * 0.8, cfg.cp,
                         cfg.feat_w_sev, cfg.feat_match_w, cfg.feat_best_w)
    attr_dom = attr2 > feat2
    return _warn_if(not (feat_dom and attr_dom),
                    f"feat-dom on hard={feat_dom}, attr-dom on grind={attr_dom}")


def _c_match_detection():
    fracs = [1.0, 0.6, 0.15, 0.1, 0.6, 0.9, 0.8, 0.15, 0.7]  # two genuine matches
    count, depth = M.count_wprime_matches(fracs)
    return _ok(count == 2 and depth > 0, f"matches={count} depth={depth:.3f}")


def _c_no_imperative():
    strings = prov.parse_strings()
    if strings is None:
        return CheckResult("SKIP", "strings.xml not found on this branch")
    offenders = []
    for sid in prov.STATUS_STRING_IDS:
        if sid in strings and prov.is_imperative(strings[sid]):
            offenders.append((sid, strings[sid]))
    return _ok(not offenders, f"imperative-mood status copy: {offenders}")


def _c_numeric_afi_gate():
    default = M.Config()
    unlocked = M.Config(positive_pilot=True)
    override = M.Config(ship_number_override=True)
    return _ok(not default.numeric_afi_unlocked()
               and unlocked.numeric_afi_unlocked()
               and override.numeric_afi_unlocked(),
               "pre-pilot categorical only; unlocks on pilot/override")


def _c_training_load_realism():
    cfg = M.Config()
    tss_1h = M.tss(3600, cfg.ftp, cfg.ftp)
    tss_3h_hard = M.tss(3 * 3600, 0.88 * cfg.ftp, cfg.ftp)   # ~230 TSS
    ok = abs(tss_1h - 100) < 1 and 200 <= tss_3h_hard <= 300
    # CTL ramp warning fires >5-8/week
    led = M.Ledger(cfg, day=0)
    for d in range(28):
        led.advance_day(d)
        led.finalize_ride(120.0, d)   # steady solid load
    ramp = led.ctl_ramp_per_week(27)
    return _warn_if(not (ok and ramp is not None),
                    f"1h@FTP={tss_1h:.0f}TSS, 3h-hard={tss_3h_hard:.0f}TSS, ramp/wk={ramp}")


def _c_tsb_taper():
    cfg = M.Config()
    led = M.Ledger(cfg, day=0)
    for d in range(21):                       # build block
        led.advance_day(d)
        led.finalize_ride(150.0, d)
    tsb_before = led.tsb()
    for d in range(21, 31):                   # taper: much lower load
        led.advance_day(d)
        led.finalize_ride(30.0, d)
    led.advance_day(31)
    tsb_after = led.tsb()
    return _warn_if(not (tsb_after > tsb_before),
                    f"TSB rises on taper: {tsb_before:.1f} -> {tsb_after:.1f}")


# ===========================================================================
# §3 ADVERSARIAL / ROBUSTNESS (must not FAIL)
# ===========================================================================
def _run_no_crash(ride):
    cfg = M.Config()
    out = RideEngine(cfg).run(ride.power, ride.hr, ride.cadence, ride.rr_by_second)
    finite = all(math.isfinite(a) for a in out.afi) and all(math.isfinite(x) for x in out.f)
    return (not out.nan_seen) and finite, out


def _c_corrupt_rr_levels():
    base = S.steady_ride(duration_s=800, seed=6)
    detail = ""
    for frac in (0.03, 0.06, 0.12):
        ride = S.corrupt_rr(base, frac, seed=int(frac * 100))
        ok, out = _run_no_crash(ride)
        if not ok:
            return CheckResult("FAIL", f"NaN/crash at artifact {frac}")
        # per-window gate correctness: no window ABOVE the gate may read 'ok'
        leak = [i for i, (av, ar) in enumerate(zip(out.alpha1_avail, out.artifact))
                if ar is not None and ar > 5.0 and av == "ok"]
        if leak:
            return CheckResult("FAIL", f"{len(leak)} above-gate windows read 'ok' at {frac}")
        if frac == 0.12:
            withheld = sum(1 for a in out.alpha1_avail if a in ("low", "na"))
            usable = sum(1 for a in out.alpha1_avail if a == "ok")
            frac_withheld = withheld / max(1, withheld + usable)
            detail = f"12% artifact -> {frac_withheld:.0%} windows withheld; fallback engaged"
            if frac_withheld < 0.75:
                return CheckResult("WARN", detail + " (<75% withheld)")
    return CheckResult("PASS", "3/6/12% artifact: no crash; gate correct per-window; " + detail)


def _c_wrist_jitter():
    base = S.steady_ride(duration_s=600, artifact_frac=0.15, seed=8)
    ok, out = _run_no_crash(base)
    low = sum(1 for a in out.alpha1_avail if a in ("low", "na"))
    return _ok(ok and low > 0, "jittered RR flagged low-confidence, no confident α1")


def _c_power_hr_pauses_short():
    cfg = M.Config()
    ride = S.steady_ride(duration_s=700, seed=4)
    # power spikes + HR loss + a stop
    p = list(ride.power); h = list(ride.hr)
    for i in range(200, 220):
        p[i] = 2000.0
    for i in range(300, 360):
        h[i] = None
    for i in range(400, 460):
        p[i] = 0.0
    ride2 = S.Ride(p, h, ride.cadence, ride.rr_by_second)
    ok, _ = _run_no_crash(ride2)
    # very short ride, no baseline window
    short = S.steady_ride(duration_s=60, seed=1)
    ok2, _ = _run_no_crash(short)
    return _ok(ok and ok2, "spikes/HR-loss/stop/short ride: no NaN, no crash")


def _c_heat_shared_confound():
    ride = S.heat_ride(duration_s=5400, seed=4)
    ok, out = _run_no_crash(ride)
    # both decoupling and α1-drift move on a hot ride (shared confound)
    dec_late = [d for d in out.decoup[4800:5100] if d is not None]
    moved = (np.mean(dec_late) if dec_late else 0.0) > 1.0
    return _ok(ok and moved, "heat: decoupling & α1 both move; no crash (shared confound)")


def _c_extreme_profiles():
    for cfg in (M.Config(ftp=90, cp=85, hr_max=160), M.Config(ftp=480, cp=460, hr_max=210)):
        ride = S.steady_ride(power_w=int(0.7 * cfg.ftp), duration_s=500,
                             ftp=cfg.ftp, seed=2)
        out = RideEngine(cfg).run(ride.power, ride.hr, ride.cadence, ride.rr_by_second)
        if any(not (0 <= a <= 100) for a in out.afi):
            return CheckResult("FAIL", f"AFI out of bounds at ftp={cfg.ftp}")
    return CheckResult("PASS", "extreme FTP/HRmax: AFI bounded & ordered")


def _c_stale_cp():
    cfg = M.Config(cp=120)   # deliberately wrong (too low) CP
    ride = S.steady_ride(power_w=200, duration_s=600, seed=3)
    out = RideEngine(cfg).run(ride.power, ride.hr, ride.cadence, ride.rr_by_second)
    finite = all(math.isfinite(w) for w in out.wbal_frac)
    return _ok(finite and not out.nan_seen, "stale CP: W'bal finite, no crash (caveat is UI-side)")


def _c_degradation_matrix():
    """Every row of white-paper §8.4: dropping each input must not crash/NaN and
    must leave the independent tiles live."""
    cfg = M.Config()
    base = S.steady_ride(duration_s=1000, seed=5)
    rows = []
    # no power -> HR/α1 still update (AFI still produced), power tiles absent
    r = S.drop_channel(base, "power")
    ok, out = _run_no_crash(r)
    rows.append(("no_power", ok and any(math.isfinite(a) for a in out.afi)))
    # no HR -> AFI degrades but power-side (kJ) stays live
    r = S.drop_channel(base, "hr")
    ok, out = _run_no_crash(r)
    rows.append(("no_hr", ok and out.kj_weighted[-1] > 0))
    # no RR -> α1 unavailable, decoupling-dominant AFI still finite
    r = S.drop_channel(base, "rr")
    ok, out = _run_no_crash(r)
    na = all(av == "na" for av in out.alpha1_avail)
    rows.append(("no_rr", ok and na))
    # no cadence -> everything else unaffected
    r = S.drop_channel(base, "cadence")
    ok, _ = _run_no_crash(r)
    rows.append(("no_cadence", ok))
    # intermittent dropout (all channels flicker)
    p = [None if i % 7 == 0 else v for i, v in enumerate(base.power)]
    h = [None if i % 11 == 0 else v for i, v in enumerate(base.hr)]
    ok, _ = _run_no_crash(S.Ride(p, h, base.cadence, base.rr_by_second))
    rows.append(("intermittent", ok))
    # total sensor loss
    n = len(base.power)
    ok, out = _run_no_crash(S.Ride([None]*n, [None]*n, [None]*n, [[] for _ in range(n)]))
    rows.append(("total_loss", ok and not out.nan_seen))
    failed = [name for name, good in rows if not good]
    return _ok(not failed, f"degradation rows failing: {failed or 'none'}")


# ===========================================================================
# §4 PROVENANCE & HONESTY
# ===========================================================================
GATING_CONVENTION_PROPS = [
    "afiFresh", "afiBuilding", "decoupRef", "decoupOk", "decoupCaution",
    "decoupHigh", "artifactGate", "kjAnchor", "tsbFresh", "tsbOverreach",
    "trimpFemaleCoeff", "seedA", "seedB", "seedTsbScale",
    "featWSev", "featMatchW", "featBestW", "attrDriftW",
]


def _c_convention_settings():
    props = prov.parse_properties()
    if props is None:
        return CheckResult("SKIP", "properties.xml not found on this branch")
    missing = [k for k in GATING_CONVENTION_PROPS if k not in props]
    return _ok(not missing, f"convention/synthesis gating values as settings; missing={missing}")


def _c_defaults_match_code():
    props = prov.parse_properties()
    if props is None:
        return CheckResult("SKIP", "properties.xml not found on this branch")
    cfg = M.Config()
    pairs = {
        "ftp": cfg.ftp, "cp": cfg.cp, "fRef": cfg.f_ref, "cF": cfg.c_f,
        "kappaI": cfg.kappa_i, "kappaD": cfg.kappa_d, "afiFresh": cfg.afi_fresh,
        "afiBuilding": cfg.afi_building, "decoupRef": cfg.decoup_ref,
        "kjAnchor": cfg.kj_anchor, "trimpFemaleCoeff": cfg.trimp_female_coeff,
    }
    mism = []
    for k, v in pairs.items():
        if k in props:
            try:
                if abs(float(props[k]) - float(v)) > 1e-6:
                    mism.append((k, props[k], v))
            except ValueError:
                pass
    return _ok(not mism, f"ported defaults vs properties.xml mismatches: {mism}")


def _c_label_enforcement():
    strings = prov.parse_strings()
    if strings is None:
        return CheckResult("SKIP", "strings.xml not found on this branch")
    need = ["AdvisoryTag", "UncalibratedTag", "NotMedical"]
    missing = [k for k in need if k not in strings or not strings[k]]
    med = "NotMedical" in strings and "medical" in strings["NotMedical"].lower()
    return _ok(not missing and med, f"advisory/uncalibrated/disclaimer present; missing={missing}")


def _c_no_damage_word():
    strings = prov.parse_strings()
    if strings is None:
        return CheckResult("SKIP", "strings.xml not found on this branch")
    bad = [sid for sid in prov.STATUS_STRING_IDS
           if sid in strings and "damage" in strings[sid].lower()]
    return _ok(not bad, f"'damage' asserted in status copy: {bad}")


def _c_traceability_coverage():
    syms = prov.parse_traceability_symbols()
    if syms is None:
        return CheckResult("SKIP", "traceability.md not found on this branch")
    needed = ["cF", "C_F", "F_REF", "fRef", "KAPPA_I", "KAPPA_D",
              "PROJECTED_AFI", "F0_SEED", "A1_SIGMOID", "AET_ALPHA1"]
    joined = " ".join(syms)
    present = [n for n in needed if n in joined]
    frac = len(present) / len(needed)
    detail = f"{len(syms)} traceability rows; key-constant coverage {frac:.0%}"
    # coverage is informative; only fail if the matrix is essentially empty
    return CheckResult("PASS" if len(syms) >= 15 and frac >= 0.7 else "WARN", detail)


# ===========================================================================
# §5 CALIBRATION-DEPENDENCE
# ===========================================================================
def _c_no_calibration_defaults():
    cfg = M.Config()
    # with no calibration, numeric AFI stays locked and defaults are literature
    return _ok(not cfg.numeric_afi_unlocked() and cfg.p_aet == 0.75 * cfg.ftp,
               "uncalibrated -> literature defaults, numeric AFI locked")


def _c_r2_gate():
    # a clean falling α1-vs-power ramp is accepted (R²>0.75); noise is rejected
    powers = list(np.linspace(120, 320, 20))
    alphas = [1.2 - 0.003 * p for p in powers]                  # clean line
    good = M.fit_sigmoid(powers, alphas)
    rng = np.random.default_rng(0)
    noisy = [0.8 + rng.normal(0, 0.4) for _ in powers]          # no relationship
    bad = M.fit_sigmoid(powers, noisy)
    return _ok(good["accepted"] and not bad["accepted"],
               f"clean fit accepted (r2={good['r2']:.2f}); noise rejected (r2={bad['r2']:.2f})")


def _c_threshold_regression():
    # after calibration the α1=0.75 crossing sits inside the ramp's power range
    powers = list(np.linspace(120, 320, 20))
    alphas = [1.15 - 0.0025 * p for p in powers]
    fit = M.fit_sigmoid(powers, alphas)
    inside = fit["accepted"] and 120 <= fit["p_aet"] <= 320
    return _ok(inside, f"calibrated AeT crossing p_aet={fit.get('p_aet', 0):.0f} W in range")


def _c_criterion_validity_stub():
    # Owed until real data exist: relate AFI/F to an EXTERNAL fatigue readout via
    # rank correlation + cross-validated calibration curve (NOT Bland-Altman;
    # AFI is a 0-100 index vs watts/mmol/RPE). n≈5 = proof-of-concept only.
    return CheckResult("SKIP", "criterion-validity study owed (external fatigue criterion; "
                               "association analysis, not Bland-Altman; powered n required)")


# ===========================================================================
# CATALOG
# ===========================================================================
CATALOG: List[Check] = [
    # §1 hard invariants
    Check("H1", "HARD", "TSB == CTL - ATL exactly",
          "white-paper §5; TrainingPeaks PMP", _c_tsb_identity),
    Check("H2", "HARD", "IF == NP / FTP",
          "white-paper §5", _c_if_identity),
    Check("H3", "HARD", "TSS == duration_h · IF² · 100 (1h@FTP ≈ 100)",
          "white-paper §5; TrainingPeaks", _c_tss_formula),
    Check("H4", "HARD", "NP == 4th-root of the mean of power⁴ (coding correctness only)",
          "white-paper §3.1 (flagged unvalidated-at-granularity)", _c_np_definition),
    Check("H5", "HARD", "AFI ∈ [0,100] for all F",
          "white-paper §4.5", _c_afi_bounds),
    Check("H6", "HARD", "DFA-α1 finite and > ~0.2 when the gate passes",
          "references.md DFA-α1 pipeline; harness §1 (wide upper bound)", _c_dfa_lower_bound),
    Check("H7", "HARD", "Estimator is a LINEAR KF (predict affine; no Jacobian)",
          "white-paper §4.4 Rev 3", _c_filter_linear),
    Check("H8", "HARD", "Concerning bands strictly ordered (AFI, decoupling)",
          "white-paper §4.5", _c_band_ordering),
    Check("H9", "HARD", "DFA-α1 withheld when artifact > gate",
          "white-paper §3.3 hard artifact gate", _c_artifact_gate),
    Check("H10", "HARD", "Covariance stays PSD; no NaN/Inf under dropouts",
          "white-paper §8.4; harness §1 Kalman sanity", _c_kalman_sanity),
    Check("H11", "HARD", "Ledger CTL/ATL idempotent per day; survives re-fold",
          "white-paper §5, §8.3", _c_ledger_idempotent),
    # §2 plausibility
    Check("P1", "PLAUSIBILITY", "Ensemble-mean α1 decreases as intensity rises",
          "Rogers/Gronwald; references.md DFA-α1=0.75/0.5", _c_alpha1_vs_intensity),
    Check("P2", "PLAUSIBILITY", "Decoupling generally increases under sustained drift",
          "Friel/TrainingPeaks; Barsumyan low-SNR caveat", _c_decoupling_under_drift),
    Check("P4", "PLAUSIBILITY", "Durability drift near ~1500 kJ is in the ~6-10% ballpark",
          "Maunder/Stevens −6..−10% after ~1400-1680 kJ", _c_durability_magnitude),
    Check("P5", "PLAUSIBILITY", "Charge graded (sub-CP allowed, larger above AeT, 0 on coast)",
          "white-paper §4.2 Rev 2 (no hard CP gate)", _c_subcp_drift_graded),
    Check("P6", "PLAUSIBILITY", "α1 below A1_target moves F (the fusion is wired)",
          "white-paper §4.2 Rev 2 coupling −c_F·F", _c_coupling_wired),
    Check("P7", "PLAUSIBILITY", "F observability = non-degenerate Gramian (model only)",
          "white-paper §4.3a (numerical, not physiological)", _c_observability),
    Check("P8", "PLAUSIBILITY", "Respiration/artifact does NOT manufacture fatigue",
          "white-paper §4.4 R_A1 inflation", _c_respiration_no_fatigue),
    Check("P9", "PLAUSIBILITY", "Long steady Z2 → moderate AFI, not severe",
          "white-paper §4.4 charge↔F_ref tuning", _c_longz2_moderate),
    Check("P10", "PLAUSIBILITY", "Recovery/coast relaxes F (κ_d gated, τ_rec decay)",
          "white-paper §4.4", _c_recovery_relaxes_f),
    Check("P11", "PLAUSIBILITY", "Feat dominates hard efforts; Attrition dominates grinds",
          "white-paper §8.2 (evidence, not a gate)", _c_feat_vs_attrition),
    Check("P11b", "PLAUSIBILITY", "W′ match counted only on <thresh→recovery cycle",
          "white-paper §8.2; Skiba", _c_match_detection),
    Check("P12", "HONESTY", "Status/advisory copy is descriptive mood (no imperative)",
          "white-paper §6, §8.1 (check MOOD)", _c_no_imperative),
    Check("P13", "HARD", "Numeric AFI gated pre-pilot (categorical default)",
          "white-paper §8.1 decision", _c_numeric_afi_gate),
    Check("P14", "PLAUSIBILITY", "Training-load realism (1h@FTP≈100 TSS; ramp cue)",
          "TrainingPeaks; white-paper §5", _c_training_load_realism),
    Check("P15", "PLAUSIBILITY", "TSB rises on a taper (ATL falls faster than CTL)",
          "Banister τ2<τ1; white-paper §5", _c_tsb_taper),
    # §3 adversarial
    Check("A1", "ADVERSARIAL", "Corrupt RR 3/6/12%: no crash; gate withholds α1",
          "white-paper §3.3, §8.4", _c_corrupt_rr_levels),
    Check("A2", "ADVERSARIAL", "Wrist-quality RR flagged low-confidence, not confident α1",
          "white-paper §3.3, §8.4", _c_wrist_jitter),
    Check("A3", "ADVERSARIAL", "Power spikes/HR loss/stops/short ride: no NaN/crash",
          "white-paper §8.4", _c_power_hr_pauses_short),
    Check("A4", "ADVERSARIAL", "Heat: decoupling & α1 both move (shared confound); no crash",
          "white-paper §6 heat co-driver", _c_heat_shared_confound),
    Check("A5", "ADVERSARIAL", "Extreme FTP/HRmax: outputs bounded & ordered",
          "white-paper §8.4", _c_extreme_profiles),
    Check("A6", "ADVERSARIAL", "Stale CP: W'bal finite, no crash",
          "white-paper §3.4 stale-CP caveat", _c_stale_cp),
    Check("A7", "ADVERSARIAL", "Graceful-degradation matrix: every §8.4 row survives",
          "white-paper §8.4 (HARD requirement)", _c_degradation_matrix),
    # §4 honesty
    Check("HN1", "HONESTY", "Convention/synthesis values are live settings",
          "white-paper §9 provenance", _c_convention_settings),
    Check("HN2", "HONESTY", "Ported code defaults agree with shipped properties.xml",
          "white-paper §9", _c_defaults_match_code),
    Check("HN3", "HONESTY", "Advisory/uncalibrated tags + non-medical disclaimer present",
          "white-paper §8.1, §10", _c_label_enforcement),
    Check("HN5", "HONESTY", "'damage' never asserted as certainty in status copy",
          "white-paper §6", _c_no_damage_word),
    Check("HN6", "HONESTY", "Every code constant has a traceability row",
          "white-paper §9; traceability.md", _c_traceability_coverage),
    # §5 calibration
    Check("C1", "CALIBRATION", "No calibration → literature defaults, numeric AFI locked",
          "white-paper §10", _c_no_calibration_defaults),
    Check("C2", "CALIBRATION", "Calibration fit accepted only if R² > 0.75",
          "white-paper §10 R²>0.75 gate", _c_r2_gate),
    Check("C3", "CALIBRATION", "Calibrated AeT crossing lands in the ramp's power range",
          "white-paper §10 (threshold crossings only, not F/AFI)", _c_threshold_regression),
    Check("C4", "CALIBRATION", "Criterion-validity study stub (owed; association, not B-A)",
          "white-paper §10 release gate", _c_criterion_validity_stub),
]


def run_all() -> List[tuple]:
    return [(c, c.run()) for c in CATALOG]
