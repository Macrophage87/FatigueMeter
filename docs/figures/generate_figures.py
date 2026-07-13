#!/usr/bin/env python3
"""Generate the fatigue-variable behaviour figures for the FatigueMeter docs.

Each figure models how one fatigue variable behaves **as fatigue increases**,
using the model equations from the white paper (§3–§5, corrected Rev-3 seed
values) and the literature-review evidence. Output is written to docs/figures/
in BOTH vector (.svg) and raster (.png) form.

Run:  python docs/figures/generate_figures.py

Design: colours follow the validated data-viz palette (CVD-checked); every
multi-series plot also uses distinct line styles + direct labels so identity is
never carried by colour alone. Status bands (fresh / building / drifting) are
always text-labelled. These curves are ILLUSTRATIVE of the modelled behaviour —
the fused AFI/advisory are synthesis-grade and unvalidated against an external
fatigue criterion (white paper §10); shapes, not calibrated magnitudes.
"""
from __future__ import annotations

import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------
# Model constants (white paper §4.4 corrected + §3/§5). Kept in sync with
# source/Constants.mc and resources/properties.xml.
# ---------------------------------------------------------------------------
FTP, CP, WPRIME = 250.0, 240.0, 20000.0
HR_MAX, HR_REST = 190.0, 50.0
P_AET = 0.75 * FTP                 # 187.5 W
G_P = 0.45                         # bpm/W  (Rev-3 correction)
F_REF = 12.0                       # bpm — AFI full-scale reference
TAU_REC = 900.0                    # s
KAPPA_I, KAPPA_D = 0.000145, 0.0028
C_F = 0.0167                       # α1 <- F coupling gain
A0, A1, S = 1.0, 0.5, 0.02         # A1_target sigmoid (crosses 0.75 at P_AeT)
AET_A1, ANT_A1 = 0.75, 0.50
DECOUP_OK, DECOUP_CAUTION, DECOUP_HIGH = 5.0, 8.0, 10.0
AFI_FRESH, AFI_BUILDING = 30.0, 60.0
KJ_ANCHOR_LOW, KJ_ANCHOR_HIGH = 1500.0, 2500.0
CTL_TAU, ATL_TAU = 42.0, 7.0
TSB_FRESH, TSB_OVERREACH = 10.0, -30.0

# ---------------------------------------------------------------------------
# Palette (validated data-viz defaults; light surface for docs)
# ---------------------------------------------------------------------------
INK, INK2, MUTED = "#0b0b0b", "#52514e", "#898781"
GRID, SURFACE = "#e1e0d9", "#ffffff"
BLUE = "#2a78d6"          # primary single-series
AQUA, YELLOW, GREEN = "#1baf7a", "#eda100", "#008300"
ORANGE, RED, VIOLET = "#eb6834", "#e34948", "#4a3aa7"
GOOD, WARN, SERIOUS, CRIT = "#0ca30c", "#fab219", "#ec835a", "#d03b3b"

plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE,
    "savefig.facecolor": SURFACE,
    "font.family": "sans-serif",
    "font.sans-serif": ["DejaVu Sans", "Arial", "Helvetica"],
    "font.size": 10.5, "axes.titlesize": 12.5, "axes.titleweight": "bold",
    "axes.labelsize": 10.5, "axes.edgecolor": "#c3c2b7", "axes.linewidth": 0.9,
    "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8,
    "xtick.color": MUTED, "ytick.color": MUTED,
    "axes.labelcolor": INK2, "text.color": INK,
    "axes.spines.top": False, "axes.spines.right": False,
    "legend.frameon": False, "legend.fontsize": 9.5,
})


def _style(ax):
    ax.tick_params(length=3, colors=MUTED)
    ax.set_axisbelow(True)
    for s in ("left", "bottom"):
        ax.spines[s].set_color("#c3c2b7")


def _fatigue_arrow(ax, y=-0.30):
    """Annotate the x-axis as the direction of increasing fatigue, placed clearly
    BELOW the x-axis label so the two never collide."""
    ax.xaxis.labelpad = 2
    ax.annotate("", xy=(0.98, y), xytext=(0.34, y), xycoords="axes fraction",
                arrowprops=dict(arrowstyle="-|>", color=MUTED, lw=1.4),
                annotation_clip=False)
    ax.annotate("increasing fatigue", xy=(0.66, y + 0.03), xycoords="axes fraction",
                ha="center", va="bottom", color=MUTED, fontsize=8.5, style="italic",
                annotation_clip=False)


def _eqn(ax, text):
    ax.text(0.03, 0.06, text, transform=ax.transAxes, fontsize=8.5,
            color=MUTED, style="italic", va="bottom")


def _illustrative(ax, loc="lower right"):
    """Stamp an on-figure honesty mark for panels likely to be shared standalone
    (§4.3a/§10 — the fused/convention curves are not validated measurements)."""
    x, ha = (0.985, "right") if "right" in loc else (0.015, "left")
    y, va = (0.03, "bottom") if "lower" in loc else (0.97, "top")
    ax.text(x, y, "illustrative · convention, not validated", transform=ax.transAxes,
            ha=ha, va=va, fontsize=7.2, color="#9a9992", style="italic",
            bbox=dict(boxstyle="round,pad=0.25", fc="#f4f4f1", ec="#dcdcd6", lw=0.6))


def save(fig, name):
    fig.tight_layout()
    for ext in ("svg", "png", "pdf"):     # vector (svg/pdf) + raster (png)
        fig.savefig(os.path.join(HERE, f"{name}.{ext}"),
                    dpi=200, bbox_inches="tight")
    plt.close(fig)
    print(f"wrote {name}.svg / .png / .pdf")


# ---------------------------------------------------------------------------
# Model helpers
# ---------------------------------------------------------------------------
def a1_target(p):
    return A0 - A1 / (1.0 + np.exp(-S * (p - P_AET)))


def hr_ss(p):
    return HR_REST + G_P * p


# Fatigue-state axis for the acute observables: F from fresh (0) to end-of-hard-
# ride reference and a little beyond.
F = np.linspace(0.0, 1.15 * F_REF, 400)
P_STEADY = P_AET                    # a heavy-domain steady effort at the AeT anchor
HRSS = hr_ss(P_STEADY)


# ===========================================================================
# 1. F — residual cardiovascular-drift state (the acute-fatigue engine)
# ===========================================================================
def fig_F():
    # Integrate F(t) explicitly so the CHARGE (heavy effort) AND the RECOVERY
    # relaxation (coast: κ_d gated off, F decays via τ_rec) are both drawn — the
    # relaxation is the behaviour that distinguishes F from a monotonic time-ramp.
    charge = KAPPA_I * max(0.0, P_STEADY + 40 - P_AET) + KAPPA_D
    f_ss = charge * TAU_REC
    coast_start = 120.0                               # min: stop pedalling (inactive)
    dt = 1.0                                          # s
    n = int(180 * 60)
    f = 0.0
    ts, fs = [], []
    for i in range(n):
        tmin = i / 60.0
        active = tmin < coast_start
        ch = charge if active else 0.0               # κ_d gated on active only
        f += (ch - f / TAU_REC) * dt
        if i % 60 == 0:
            ts.append(tmin); fs.append(f)
    ts, fs = np.array(ts), np.array(fs)
    fig, ax = plt.subplots(figsize=(6.4, 3.7))
    ax.axvspan(coast_start, 180, color=GOOD, alpha=0.07)
    ax.plot(ts, fs, color=BLUE, lw=2.3)
    ax.axhline(f_ss, color=MUTED, lw=1, ls=":", zorder=1)
    ax.text(4, f_ss + 0.15, f"F_ss = charge·τ_rec ≈ {f_ss:.1f} bpm", color=MUTED, fontsize=8.5)
    ax.axvline(coast_start, color=GREEN, ls="--", lw=1.1)
    ax.text(coast_start + 2, fs.max() * 0.55, "coast / stop\n(κ_d off → F relaxes)",
            color=GREEN, fontsize=8.3, va="center")
    ax.text(60, fs[10] * 0.5, "charge\n(heavy effort)", color=MUTED, fontsize=8.3,
            ha="center", va="center")
    ax.set_title("Residual cardiovascular-drift state  F")
    ax.set_xlabel("time on task (min)")
    ax.set_ylabel("F  (bpm of unexplained HR drift)")
    ax.set_ylim(0, f_ss * 1.15)
    _eqn(ax, r"dF/dt = [κ_i·max(0,P−P_AeT) + κ_d(active)] − F/τ_rec")
    _style(ax)
    save(fig, "01_F_drift_state")


# ===========================================================================
# 2. AFI — Acute Fatigue Index (index, not a measurement)
# ===========================================================================
def fig_AFI():
    afi = 100.0 * np.clip(F / F_REF, 0, 1)
    fig, ax = plt.subplots(figsize=(6.2, 3.7))
    # status bands (always text-labelled — colour never alone)
    ax.axhspan(0, AFI_FRESH, color=GOOD, alpha=0.10)
    ax.axhspan(AFI_FRESH, AFI_BUILDING, color=WARN, alpha=0.13)
    ax.axhspan(AFI_BUILDING, 100, color=CRIT, alpha=0.10)
    for y0, y1, lbl, c in [(0, AFI_FRESH, "FRESH / PRODUCTIVE", GOOD),
                           (AFI_FRESH, AFI_BUILDING, "FATIGUE BUILDING", "#a9760a"),
                           (AFI_BUILDING, 100, "DURABILITY MARKERS DRIFTING", CRIT)]:
        ax.text(0.35, (y0 + y1) / 2, lbl, color=c, fontsize=8.3, va="center", weight="bold")
    ax.plot(F, afi, color=BLUE, lw=2.4)
    ax.set_title("Acute Fatigue Index  AFI  (0–100 index)")
    ax.set_xlabel("fatigue state  F  (bpm)")
    ax.set_ylabel("AFI")
    ax.set_ylim(0, 100)
    _eqn(ax, r"AFI = 100 · clamp(F / F_ref, 0, 1)")
    _fatigue_arrow(ax)
    _illustrative(ax, "upper left")
    _style(ax)
    save(fig, "02_AFI_index")


# ===========================================================================
# 3. DFA-α1 — two panels: (a) power map crossing 0.75 at AeT; (b) fatigue drift
# ===========================================================================
def fig_alpha1():
    fig, (axL, axR) = plt.subplots(1, 2, figsize=(9.6, 3.9))
    # (a) population power->α1 sigmoid. The 0.75 crossing at P_AeT is a genuine
    # anchor; 0.50 is only the P→∞ LOWER ASYMPTOTE of the sigmoid, NOT a finite
    # threshold crossing (white paper §9: the 0.5 anchor is weak — not a band
    # boundary). Draw 0.75 as an anchor line, 0.50 as an asymptote guide only.
    p = np.linspace(0.35 * FTP, 1.35 * FTP, 400)
    axL.plot(p, a1_target(p), color=BLUE, lw=2.3)
    axL.axhline(AET_A1, color=MUTED, ls=":", lw=1)
    axL.text(p[0], AET_A1 + 0.012, "0.75 AeT anchor (crossed at P_AeT)", color=MUTED, fontsize=8)
    axL.axhline(ANT_A1, color=MUTED, ls=(0, (1, 3)), lw=0.9)
    axL.text(p[0], ANT_A1 + 0.012, "0.50 lower asymptote (P → ∞, not an anchor)",
             color="#a8a7a0", fontsize=8, style="italic")
    axL.axvline(P_AET, color=GREEN, ls="--", lw=1.2)
    axL.text(P_AET + 4, 1.02, "P_AeT", color=GREEN, fontsize=8.5)
    axL.set_title("(a)  Power → DFA-α1 map")
    axL.set_xlabel("power (W)  →  increasing intensity")
    axL.set_ylabel("DFA-α1")
    axL.set_ylim(0.42, 1.08)
    _eqn(axL, r"A1_target(P) = a0 − a1/(1+e^{−s(P−P_AeT)}),  a0=1.0, a1=0.5")
    _style(axL)
    # (b) α1 drift below baseline-for-power as fatigue rises (single clean annotation)
    a1_fat = a1_target(P_STEADY) - C_F * F
    axR.axhline(a1_target(P_STEADY), color=MUTED, ls=":", lw=1)
    axR.text(0.2, a1_target(P_STEADY) + 0.008, "baseline-for-power (fresh)", color=MUTED, fontsize=8)
    axR.plot(F, a1_fat, color=BLUE, lw=2.3)
    axR.annotate("drift below baseline = fatigue signal",
                 xy=(F[-1] * 0.86, a1_fat[int(len(F) * 0.86)]),
                 xytext=(F[-1] * 0.06, a1_fat[-1] + 0.008), color=INK2, fontsize=8.5,
                 arrowprops=dict(arrowstyle="-|>", color=MUTED, lw=1.2))
    axR.set_title("(b)  α1 drift with fatigue (fixed power)")
    axR.set_xlabel("fatigue state  F  (bpm)")
    axR.set_ylabel("DFA-α1")
    _fatigue_arrow(axR)
    _style(axR)
    save(fig, "03_DFA_alpha1")


# ===========================================================================
# 4. Aerobic decoupling %
# ===========================================================================
def fig_decoupling():
    dec = 100.0 * F / (HRSS + F)                       # EF drop from HR drift
    fig, ax = plt.subplots(figsize=(6.2, 3.7))
    ax.axhspan(0, DECOUP_OK, color=GOOD, alpha=0.10)
    ax.axhspan(DECOUP_OK, DECOUP_CAUTION, color=WARN, alpha=0.13)
    ax.axhspan(DECOUP_CAUTION, dec.max() * 1.05, color=CRIT, alpha=0.10)
    for y, lbl, c in [(DECOUP_OK / 2, "<5%  healthy", GOOD),
                      ((DECOUP_OK + DECOUP_CAUTION) / 2, "5–8%  caution", "#a9760a"),
                      (DECOUP_CAUTION + 0.6, ">8%  above-threshold / depleted", CRIT)]:
        ax.text(0.2, y, lbl, color=c, fontsize=8.3, va="center", weight="bold")
    ax.plot(F, dec, color=BLUE, lw=2.4)
    ax.set_title("Aerobic decoupling %  (EF drift)")
    ax.set_xlabel("fatigue state  F  (bpm)")
    ax.set_ylabel("decoupling %")
    _eqn(ax, r"decoupling% = (EF_base − EF)/EF_base ·100 = 100·F/(HR_ss+F)")
    _fatigue_arrow(ax)
    _illustrative(ax, "lower right")
    _style(ax)
    save(fig, "04_decoupling")


# ===========================================================================
# 5. Efficiency Factor
# ===========================================================================
def fig_ef():
    ef = P_STEADY / (HRSS + F)                          # NP/HR (NP≈P steady)
    fig, ax = plt.subplots(figsize=(6.2, 3.7))
    ax.plot(F, ef, color=BLUE, lw=2.4)
    ax.axhline(ef[0], color=MUTED, ls=":", lw=1)
    ax.text(0.2, ef[0] + 0.004, "fresh EF baseline", color=MUTED, fontsize=8)
    ax.set_title("Efficiency Factor  EF = NP / HR")
    ax.set_xlabel("fatigue state  F  (bpm)")
    ax.set_ylabel("EF  (W per bpm)")
    _eqn(ax, r"EF = NP / (HR_ss + F)  — declines as drift lifts HR")
    _fatigue_arrow(ax)
    _style(ax)
    save(fig, "05_efficiency_factor")


# ===========================================================================
# 6. HR at fixed power (cardiovascular drift)
# ===========================================================================
def fig_hr():
    hr = HRSS + F
    fig, ax = plt.subplots(figsize=(6.2, 3.7))
    ax.set_ylim(HRSS - 3.0, hr.max() + 1.5)            # headroom so labels don't collide
    ax.plot(F, hr, color=BLUE, lw=2.4)
    ax.axhline(HRSS, color=MUTED, ls=":", lw=1)
    # place the HR_ss note to the RIGHT of the plot, above its line — clear of the
    # equation annotation in the lower-left.
    ax.text(F[-1] * 0.98, HRSS + 0.6, "HR_ss  (fresh HR for this power)",
            color=MUTED, fontsize=8, ha="right", va="bottom")
    ax.set_title("Heart rate at fixed power")
    ax.set_xlabel("fatigue state  F  (bpm)")
    ax.set_ylabel("HR  (bpm)")
    _eqn(ax, r"HR = HR_ss + F,   HR_ss = HR_rest + g_P·P")
    _fatigue_arrow(ax)
    _style(ax)
    save(fig, "06_hr_drift")


# ===========================================================================
# 7. Cadence drift (corroborating vote)
# ===========================================================================
def fig_cadence():
    # A WEAK corroborator, not a law: Barsumyan found cadence decline r≈0.40 (~16%
    # variance), direction-ambiguous (cadence→decoupling, not fatigue→cadence), no
    # threshold, observed magnitude only ~2%. Render it as a low-confidence CLOUD
    # around a faint mean trend, not a clean deterministic line.
    rng = np.random.default_rng(11)
    phi = F / F_REF
    mean_trend = 2.0 * phi                              # ~2% observed at end-of-hard-ride
    # scatter with SD ≈ mean -> r²≈0.16 (r≈0.40)
    fsamp = np.linspace(0.3, 1.1, 60) * F_REF
    ph = fsamp / F_REF
    obs = 2.0 * ph + rng.normal(0, 1.4, len(fsamp))
    fig, ax = plt.subplots(figsize=(6.2, 3.7))
    ax.axhline(0, color=MUTED, lw=0.8)
    ax.scatter(fsamp, obs, s=16, color=BLUE, alpha=0.45, edgecolor="none",
               label="per-rider observations (r≈0.40)")
    ax.plot(F, mean_trend, color=BLUE, lw=1.6, ls="--", label="mean trend (~2% at F_ref)")
    ax.set_title("Cadence decline  (weak corroborator)")
    ax.set_xlabel("fatigue state  F  (bpm)")
    ax.set_ylabel("cadence decline  (%)")
    ax.legend(loc="upper left", fontsize=8)
    _eqn(ax, r"r≈0.40 (~16% variance), direction-ambiguous, no threshold — low weight")
    _fatigue_arrow(ax)
    _illustrative(ax, "lower right")
    _style(ax)
    save(fig, "07_cadence_drift")


# ===========================================================================
# 8. W′bal — anaerobic reserve depletion & "matches"
# ===========================================================================
def fig_wbal():
    dt = 1.0
    T = 1800
    w = WPRIME
    frac = WPRIME * 0.20
    ts, ws = [], []
    in_match = False
    match_pts = []
    for i in range(T):
        # 105 s hard @ 400 W (deep, dips below 20%), 150 s easy @ 140 W (recover)
        p = 400.0 if (i % 255) < 105 else 140.0
        if p >= CP:
            w = w - (p - CP) * dt
        else:
            w = w + (CP - p) * (WPRIME - w) / WPRIME * dt
        w = min(max(w, 0.0), WPRIME)
        # a 'match' = dip below 20% then recovery back above 50%
        if not in_match and w < frac:
            in_match = True
            match_pts.append(i)
        elif in_match and w > 0.5 * WPRIME:
            in_match = False
        ts.append(i / 60.0); ws.append(w / WPRIME * 100.0)
    ts, ws = np.array(ts), np.array(ws)
    fig, ax = plt.subplots(figsize=(6.4, 3.7))
    ax.axhspan(0, 20, color=CRIT, alpha=0.10)
    ax.text(0.98, 3.0, "match zone (<20% W′)", color=CRIT, fontsize=8.3,
            va="center", ha="right", weight="bold")
    ax.plot(ts, ws, color=BLUE, lw=1.8)
    for sidx in match_pts:
        ax.plot(ts[sidx], ws[sidx], "o", color=CRIT, ms=6, zorder=5)
    ax.text(0.98, 0.95, f"{len(match_pts)} matches burned", transform=ax.transAxes,
            ha="right", va="top", color=CRIT, fontsize=9.5, weight="bold")
    ax.set_title("W′bal — anaerobic reserve  &  'matches'")
    ax.set_xlabel("time on an interval effort (min)  →  more matches = more fatigue")
    ax.set_ylabel("W′bal  (% of W′)")
    ax.set_ylim(0, 100)
    _style(ax)
    save(fig, "08_wprime_bal")


# ===========================================================================
# 9. Intensity-weighted kJ — the durability clock
# ===========================================================================
def _weight_for_power(p):
    if p <= CP:
        return 1.0
    return 1.0 + min(max((p - CP) / CP, 0.0), 1.0) * 2.0    # 1× at CP → 3× at 2·CP


def fig_kj():
    # Use a MIXED profile with supra-CP surges so the intensity weighting is
    # actually exercised (a sub-CP steady ride has w≡1 and the weighting is
    # invisible). Plot raw vs intensity-weighted kJ — they diverge on the surges.
    dt = 1.0
    T = int(4.0 * 3600)
    rng = np.random.default_rng(3)
    raw = 0.0; wtd = 0.0
    ts, raws, wtds = [], [], []
    for i in range(T):
        # tempo base ~0.8·FTP with repeated ~5-min supra-threshold surges @ 1.25·CP
        surge = (i % 1200) < 300
        p = (1.25 * CP if surge else 0.80 * FTP) + rng.normal(0, 5)
        p = max(0.0, p)
        raw += p * dt / 1000.0
        wtd += _weight_for_power(p) * p * dt / 1000.0
        if i % 60 == 0:
            ts.append(i / 3600.0); raws.append(raw); wtds.append(wtd)
    ts, raws, wtds = np.array(ts), np.array(raws), np.array(wtds)
    fig, ax = plt.subplots(figsize=(6.6, 3.9))
    ax.plot(ts, wtds, color=BLUE, lw=2.4, ls="-", label="intensity-weighted kJ (durability clock)")
    ax.plot(ts, raws, color=MUTED, lw=1.8, ls="--", label="raw kJ (volume only)")
    ax.text(ts[-1] * 0.62, (wtds[int(len(ts)*0.62)] + raws[int(len(ts)*0.62)]) / 2,
            "weighting\ndiverges on\nsupra-CP surges", color=INK2, fontsize=8, ha="center")
    for anch, lbl, c in [(KJ_ANCHOR_LOW, "developing anchor ~1500 kJ", "#a9760a"),
                         (KJ_ANCHOR_HIGH, "trained anchor ~2500 kJ", CRIT)]:
        ax.axhline(anch, color=c, ls=":", lw=1.1)
        ax.text(0.05, anch + 40, lbl, color=c, fontsize=8.3, weight="bold")
    ax.set_title("Intensity-weighted kJ — durability clock")
    ax.set_xlabel("time on task (h)  →  accumulating work")
    ax.set_ylabel("kJ")
    ax.legend(loc="lower right", fontsize=8.5)
    _eqn(ax, r"kJ_w = Σ w(P)·P·Δt/1000,  w=1 below CP → ~3× at 2·CP")
    _style(ax)
    save(fig, "09_kj_durability_clock")


# ===========================================================================
# 10. CTL / ATL / TSB — residual (training-scale) fatigue
# ===========================================================================
def fig_ctl_atl_tsb():
    days = np.arange(0, 42)
    load = 120.0
    ctl = np.zeros_like(days, float); atl = np.zeros_like(days, float)
    ctl[0] = 70; atl[0] = 70
    for d in range(1, len(days)):
        # build block days 0-27, taper 28+
        L = load if d < 28 else 40.0
        ctl[d] = ctl[d - 1] + (L - ctl[d - 1]) / CTL_TAU
        atl[d] = atl[d - 1] + (L - atl[d - 1]) / ATL_TAU
    tsb = ctl - atl
    fig, ax = plt.subplots(figsize=(6.6, 3.9))
    ax.plot(days, ctl, color=BLUE, lw=2.2, ls="-", label="CTL (fitness, 42 d)")
    ax.plot(days, atl, color=ORANGE, lw=2.2, ls="--", label="ATL (fatigue, 7 d)")
    ax.plot(days, tsb, color=GREEN, lw=2.2, ls="-.", label="TSB = CTL − ATL (form)")
    ax.axhline(0, color=MUTED, lw=0.8)
    ax.axhline(TSB_OVERREACH, color=CRIT, ls=":", lw=1)
    ax.text(1, TSB_OVERREACH + 1.5, "TSB < −30  high overreaching risk", color=CRIT, fontsize=8)
    ax.axvline(28, color=MUTED, ls=":", lw=1)
    ax.text(28.4, ax.get_ylim()[1] * 0.9, "taper", color=MUTED, fontsize=8.5)
    # direct labels (identity not colour-alone)
    ax.text(days[-1] + 0.3, ctl[-1], "CTL", color=BLUE, fontsize=9, va="center", weight="bold")
    ax.text(days[-1] + 0.3, atl[-1], "ATL", color=ORANGE, fontsize=9, va="center", weight="bold")
    ax.text(days[-1] + 0.3, tsb[-1], "TSB", color=GREEN, fontsize=9, va="center", weight="bold")
    ax.set_title("Residual load:  CTL / ATL / TSB")
    ax.set_xlabel("day of a build block  →  accumulating residual fatigue")
    ax.set_ylabel("TSS-scale units")
    ax.legend(loc="lower right", ncol=1)
    _style(ax)
    save(fig, "10_ctl_atl_tsb")


# ===========================================================================
# 11. RMSSD vs personal 7-day baseline ±1 SD
# ===========================================================================
def fig_rmssd():
    rng = np.random.default_rng(7)
    days = np.arange(0, 30)
    base = 52.0
    rmssd = base + rng.normal(0, 3, len(days))
    rmssd[16:] = rmssd[16:] - np.linspace(2, 16, len(days) - 16)   # overreaching decline
    roll = np.array([rmssd[max(0, i - 6):i + 1].mean() for i in range(len(days))])
    sd = np.array([rmssd[max(0, i - 6):i + 1].std() if i >= 2 else 3.0 for i in range(len(days))])
    fig, ax = plt.subplots(figsize=(6.6, 3.9))
    ax.fill_between(days, roll - sd, roll + sd, color=BLUE, alpha=0.12, label="personal baseline ±1 SD")
    ax.plot(days, roll, color=MUTED, lw=1.3, ls="--", label="7-day rolling baseline")
    ax.plot(days, rmssd, color=BLUE, lw=1.9, label="morning RMSSD")
    # flag only the SUSTAINED below-band run (single dips are noise, not a flag)
    below = rmssd < (roll - sd)
    flag = below & (days >= 15)
    ax.plot(days[flag], rmssd[flag], "o", color=CRIT, ms=6, zorder=5)
    ax.text(0.98, 0.06, "sustained decline below −1 SD → overreaching flag",
            transform=ax.transAxes, ha="right", color=CRIT, fontsize=8.3, weight="bold")
    ax.set_title("Resting HRV (RMSSD) vs personal baseline")
    ax.set_xlabel("day  →  accumulating residual fatigue")
    ax.set_ylabel("RMSSD  (ms)")
    ax.legend(loc="upper right")
    _illustrative(ax, "lower left")
    _style(ax)
    save(fig, "11_rmssd_baseline")


# ===========================================================================
# 12. FeatScore vs AttritionScore — the two flavours of "red"
# ===========================================================================
def fig_feat_attrition():
    x = np.linspace(0, 1, 200)                          # normalised effort / fatigue
    feat = 100 * x ** 1.4                               # bought with output
    attr = 100 * x ** 1.9                               # bought with drift
    fig, ax = plt.subplots(figsize=(6.4, 3.7))
    ax.plot(x, feat, color=YELLOW, lw=2.4, ls="-", label="FeatScore (output-bought red)")
    ax.plot(x, attr, color=RED, lw=2.4, ls="--", label="AttritionScore (drift-bought red)")
    ax.legend(loc="upper left")   # identity via legend + line style (no end-labels)
    ax.set_title("Feat of Strength vs Attrition  (context, not a gate)")
    ax.set_xlabel("high-fatigue effort  →  more accumulated fatigue")
    ax.set_ylabel("score (arb. units)")
    _eqn(ax, "Feat ∝ kJ>CP + severe-time + matches;  Attrition ∝ drift past anchor")
    _illustrative(ax, "lower right")
    _style(ax)
    save(fig, "12_feat_vs_attrition")


# ===========================================================================
# Overview grid (small multiples) — one image for the READMEs
# ===========================================================================
def fig_overview():
    fig, axs = plt.subplots(3, 3, figsize=(11.5, 9.2))
    afi = 100 * np.clip(F / F_REF, 0, 1)
    dec = 100 * F / (HRSS + F)
    a1_fat = a1_target(P_STEADY) - C_F * F
    ef = P_STEADY / (HRSS + F)
    hr = HRSS + F
    panels = [
        (F, afi, "AFI (0–100)", "F (bpm)", "AFI", True),
        (F, a1_fat, "DFA-α1", "F (bpm)", "α1", False),
        (F, dec, "Decoupling %", "F (bpm)", "%", True),
        (F, ef, "Efficiency Factor", "F (bpm)", "W/bpm", False),
        (F, hr, "HR at fixed power", "F (bpm)", "bpm", False),
        (F, 2 * F / F_REF, "Cadence decline % (weak)", "F (bpm)", "%", False),
    ]
    for ax, (xx, yy, title, xl, yl, up) in zip(axs.flat[:6], panels):
        ax.plot(xx, yy, color=BLUE, lw=2.0)
        ax.set_title(title, fontsize=11)
        ax.set_xlabel(xl, fontsize=8.5); ax.set_ylabel(yl, fontsize=8.5)
        _style(ax)
    # kJ clock — weighted vs raw on a mixed/supra-CP profile (weighting visible)
    tt = np.linspace(0, 4, 240)
    p_series = np.where((np.arange(len(tt)) % 60) < 15, 1.25 * CP, 0.80 * FTP)
    dts = (tt[1] - tt[0]) * 3600
    wraw = np.cumsum(p_series) * dts / 1000
    wwtd = np.cumsum([_weight_for_power(p) * p for p in p_series]) * dts / 1000
    axs.flat[6].plot(tt, wwtd, color=BLUE, lw=2.0, label="weighted")
    axs.flat[6].plot(tt, wraw, color=MUTED, lw=1.6, ls="--", label="raw")
    axs.flat[6].axhline(2000, color=CRIT, ls=":", lw=1)
    axs.flat[6].set_title("kJ durability clock", fontsize=11)
    axs.flat[6].set_xlabel("h", fontsize=8.5); axs.flat[6].set_ylabel("kJ", fontsize=8.5)
    axs.flat[6].legend(fontsize=7.5, loc="upper left")
    _style(axs.flat[6])
    # CTL/ATL/TSB
    days = np.arange(0, 42); ctl = np.zeros(42); atl = np.zeros(42); ctl[0] = atl[0] = 70
    for d in range(1, 42):
        L = 120 if d < 28 else 40
        ctl[d] = ctl[d - 1] + (L - ctl[d - 1]) / CTL_TAU
        atl[d] = atl[d - 1] + (L - atl[d - 1]) / ATL_TAU
    axs.flat[7].plot(days, ctl, color=BLUE, lw=1.8, label="CTL")
    axs.flat[7].plot(days, atl, color=ORANGE, lw=1.8, ls="--", label="ATL")
    axs.flat[7].plot(days, ctl - atl, color=GREEN, lw=1.8, ls="-.", label="TSB")
    axs.flat[7].set_title("CTL / ATL / TSB", fontsize=11)
    axs.flat[7].set_xlabel("day", fontsize=8.5); axs.flat[7].legend(fontsize=7.5, loc="center right")
    _style(axs.flat[7])
    # Feat vs Attrition
    x = np.linspace(0, 1, 150)
    axs.flat[8].plot(x, 100 * x ** 1.4, color=YELLOW, lw=2.0, label="Feat")
    axs.flat[8].plot(x, 100 * x ** 1.9, color=RED, lw=2.0, ls="--", label="Attrition")
    axs.flat[8].set_title("Feat vs Attrition", fontsize=11)
    axs.flat[8].set_xlabel("effort", fontsize=8.5); axs.flat[8].legend(fontsize=7.5, loc="upper left")
    _style(axs.flat[8])

    fig.suptitle("FatigueMeter — modelled behaviour of each fatigue variable with increasing fatigue",
                 fontsize=13.5, weight="bold", y=1.0)
    save(fig, "00_overview")


def main():
    fig_overview()
    fig_F(); fig_AFI(); fig_alpha1(); fig_decoupling(); fig_ef(); fig_hr()
    fig_cadence(); fig_wbal(); fig_kj(); fig_ctl_atl_tsb(); fig_rmssd()
    fig_feat_attrition()
    print("all figures written to", HERE)


if __name__ == "__main__":
    main()
