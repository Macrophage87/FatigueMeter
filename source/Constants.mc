using Toybox.Lang;

//! FatigueMeter — centralised physiological constants.
//!
//! RULE (white paper §9): no physiological constant may appear anywhere else in
//! the code. Every symbol below has a row in docs/traceability.md mapping it to
//! its white-paper §9 provenance and its references.md source, WITH the
//! evidence-strength note. A constant with no traceability row is a defect.
//!
//! Constants flagged "convention" or "synthesis" in §9 are NOT frozen here — they
//! are only the *defaults*; the live values are read from Application.Properties
//! (see Config.mc) so that changing a setting changes behaviour. The values here
//! are the documented defaults and the immutable, genuinely-validated anchors.
module Constants {

    // ---- DFA-α1 population anchors (white paper §9; Rogers/Gronwald) ----
    // Extraction High; evidence: group-level only, ±10 bpm individual LoA, n=15,
    // male-dominated, lab. AeT anchor is a *display/fallback* default, never the
    // sole gate (bands use per-athlete drift — §4.5).
    const AET_ALPHA1 = 0.75;      // α1 at aerobic threshold
    const ANT_ALPHA1 = 0.50;      // α1 at anaerobic threshold — DISPLAY ONLY (weak, r≈0.71)

    // Per-athlete α1 drift-below-baseline flags (synthesis; absolute <0.5 RETIRED).
    const ALPHA1_DRIFT_HIGH = 0.2;   // ≳0.2 below baseline-for-power → high fatigue vote
    const ALPHA1_DRIFT_SEVERE = 0.3; // ≳0.3 below baseline-for-power → severe vote

    // ---- Decoupling bands (Friel/TrainingPeaks convention — defaults only) ----
    const DECOUP_OK = 5.0;        // <5%  healthy
    const DECOUP_CAUTION = 8.0;   // 5-8% caution
    const DECOUP_HIGH = 10.0;     // >8-10% above-threshold / depleted

    // ---- kJ durability anchors (Spragg / durability review; population-level) ----
    const KJ_ANCHOR_LOW = 1500.0;   // developing / U23-like
    const KJ_ANCHOR_HIGH = 2500.0;  // well-trained

    // (Rev 5) CTL/ATL EWMA time constants and Friel TSB bands removed with the
    // on-device cross-ride training-load state — the field no longer computes
    // CTL/ATL/TSB (see TrainingLoadLedger; only per-ride load is exported).

    // ---- Kalman seeds / gains (white paper §4.4 — SYNTHESIS / hand-set) ----
    // No on-bike ground truth (§10). Defaults only; live values from Config.
    const TAU_HR = 30.0;     // HR kinetics
    const TAU_A = 90.0;      // α1 responds slowly
    const TAU_REC = 900.0;   // within-ride partial recovery — UNSOURCED engineering guess
    // Static power->HR gain: HR_ss = HR_rest + G_P*P must ~= the FRESH HR the
    // power elicits, else F absorbs a static-gain error and AFI saturates. The
    // model-consistency harness flagged the white paper's =~0.15 (which implies
    // P_max~=930 W, a sprint peak) as producing a saturated AFI on a plain Z2
    // ride, violating §4.4's own "long Z2 -> moderate" requirement. The correct
    // denominator is the power AT HR_max (~threshold): (190-50)/~310 ~= 0.45.
    // Synthesis / hand-set (§9) and a live setting - calibrate per athlete.
    const G_P = 0.45;        // static power->HR gain, bpm/W
    // A1_target sigmoid. The white paper says it passes through the α1=0.75 AeT
    // anchor at P_AeT, but its stated a0/a1 = 1.1/0.6 give a midpoint value of
    // a0 − a1/2 = 0.80, NOT 0.75 (the model-consistency harness flagged the
    // ~0.05 drift between this population prior and the calibrated 0.75 crossing).
    // a0=1.0, a1=0.5 fixes it: midpoint = 1.0 − 0.25 = 0.75 at P_AeT, with clean
    // asymptotes 1.0 (rest) and 0.5 (the AnT anchor). Synthesis / settings (§9).
    const SIG_A0 = 1.0;      // A1_target sigmoid upper asymptote (α1 at rest)
    const SIG_A1 = 0.5;      // A1_target sigmoid span (upper − lower asymptote)
    const SIG_S = 0.02;      // A1_target sigmoid slope (1/W)
    // Charge dynamics: dF/dt = charge − F/τ_rec, so steady state F_ss = charge·τ_rec
    // and F(t) = F_ss·(1 − e^(−t/τ_rec)).
    // κ_i tuned so 30 min at P_AeT+80 W lifts F ≈ 8-10 bpm (τ_rec=900):
    //   F(1800) = F_ss·(1−e^(−2)) = 0.865·F_ss ; want ≈9 -> F_ss≈10.4
    //   charge_i = κ_i·80 = F_ss/τ_rec = 10.4/900 = 0.0116 -> κ_i ≈ 1.45e-4.
    const KAPPA_I = 0.000145; // intensity charge (per W above P_AeT, per s)
    // κ_d tuned so F rises ~2-3 bpm over 2 h at Z2 (below P_AeT -> κ_d only):
    //   F_ss = κ_d·τ_rec ≈ 2.5 -> κ_d ≈ 2.5/900 ≈ 2.8e-3.
    const KAPPA_D = 0.0028;  // duration/thermal charge (per s, active only)
    const C_F = 0.0167;      // α1<-F coupling: F=F_ref(12) pulls α1 ~0.2 below predicted -> 0.2/12
    const F_REF = 12.0;      // AFI scale ref (bpm) — AFI linear in 1/F_ref (§4.5)

    // ---- Sanity bounds (convention / engineering glitch-rejection, §9) ----
    // These are NOT physiological anchors: they only keep sensor garbage out of
    // the filter so one bad sample can't corrupt the ride (#23). Traceability
    // rows flag them convention/glitch-rejection, not a VO2/FTP claim.
    // Absolute ceiling on one power sample. 3000 W sits unambiguously above any
    // human sprint peak (even elite track sprinters top out ~2000-2500 W for
    // <1 s), so it never clips a real effort; it exists only to reject dropouts
    // that report 0/negative or a 65535-style spike before they enter the filter
    // input u.
    const POWER_SANITY_MAX = 3000.0;   // W
    // Minimum VALID (non-dropout) power samples in the 10-min window before the
    // steadiness/stationarity gates will report confident "steady" (#19). With
    // dropout sentinels excluded, too few observed samples can't establish
    // stationarity, so the gates fall to low-confidence below this floor.
    const MIN_VALID_POWER = 30;        // samples (~30 s at 1 Hz)
    // Plausible latent-HR clamp band for x[S_HR]. Floor well below any resting HR;
    // the ceiling used in code is hrMax + HR_STATE_MARGIN, so a genuine max effort
    // is never clipped but a spike/NaN cannot leave latentHr() unbounded.
    const HR_STATE_MIN = 20.0;         // bpm
    const HR_STATE_MARGIN = 15.0;      // bpm above hrMax

    // Process / measurement noise (hand-set; no ground truth to tune against)
    const Q_HR = 0.5;
    const Q_HRLAT = 0.5;
    const Q_A1 = 0.002;
    const Q_F = 0.05;
    const R_HR = 4.0;        // σ_HR = 2 bpm -> 4
    const R_A1 = 0.0225;     // σ_A1 = 0.15 -> 0.0225

    // Initial covariance P0 = diag(25, 25, 0.09, 4)
    const P0_HR = 25.0;
    const P0_HRLAT = 25.0;
    const P0_A1 = 0.09;
    const P0_F = 4.0;

    // ---- AFI bands (convention, F_ref-dependent — must be calibrated) ----
    const AFI_FRESH_MAX = 30.0;
    const AFI_BUILDING_MAX = 60.0;
    const AFI_HIGH_MAX = 85.0;   // "AFI>85" is an absolute HR-drift cutoff in disguise (§4.5)

    // ---- W′ match (Skiba; established) ----
    const WPRIME_MATCH_FRAC = 0.20;   // W'bal drops below 20% then recovers

    // ---- Banister/Edwards TRIMP ----
    // Male: 0.64·e^(1.92x). Female coeff UNRESOLVED across secondary sources
    // (0.86 vs 0.64) — shipped as a SETTING (default 0.86, per Banister 1991
    // primary) rather than a frozen constant. references.md flags this a defect.
    const TRIMP_MALE_COEFF = 0.64;
    const TRIMP_MALE_EXP = 1.92;
    const TRIMP_FEMALE_COEFF_DEFAULT = 0.86;
    const TRIMP_FEMALE_EXP = 1.67;

    // ---- DFA pipeline parameters (white paper §3.3 / §4 lit review) ----
    const DFA_WINDOW_S = 120;      // 2-min RR window
    const DFA_RECOMPUTE_S = 5;     // recompute every 5 s
    const DFA_BOX_MIN = 4;         // box sizes 4..16 beats
    const DFA_BOX_MAX = 16;
    const DFA_R2_GATE = 0.75;      // calibration sigmoid fit acceptance (§10)
    // Plausible α1 OUTPUT band (#15): a finite DFA α1 outside this range is a
    // short/noisy-window artifact, not a real reading, so DfaAlpha1.compute drops
    // it to the invalid sentinel instead of feeding an impossible value forward.
    const ALPHA1_PLAUSIBLE_MIN = 0.2;   // below -> uncorrelated noise / artifact
    const ALPHA1_PLAUSIBLE_MAX = 1.7;   // above -> impossible (correlated ceiling ~1.5 + headroom)
    const RR_STALE_S = 10;         // no fresh RR for this long -> α1 unavailable (§8.4 staleness timer)
    // ---- HRM staleness (§8.4 staleness timer, mirror of RR_STALE_S) (#11) ----
    const HR_STALE_S = 5;          // no fresh HR page for this long -> hold value but mark STALE
    const HR_UNAVAIL_S = 15;       // no fresh HR page for this long -> HR UNAVAILABLE
    // ---- ANT+ RR lifecycle (engineering conventions / glitch-rejection) (#24) ----
    const RR_FWD_MAX = 16;         // max forward beat-count step still treated as in-sync (else RESYNC)
    const RR_WATCHDOG_MS = 40000;  // no decoded page this long while open -> forced channel restart (> ~30 s search)
    const RR_BUF_MAX = 256;        // cap the buffered RR list if the compute loop stalls (drop oldest)

    // ---- Decoupling / steadiness gate (white paper §3.1) ----
    const EF_BASELINE_START_S = 300;   // baseline window minutes 5..15
    const EF_BASELINE_END_S = 900;
    const DURABILITY_MIN_S = 3600;     // advisory needs >=60-90 min of work

    // AFI_decoup common-scale reference: decoupling% that maps to AFI≈F_ref band.
    // Chosen so AFI_decoup ≈ AFI_kalman at F_ref (§4.5). ~8% decoupling ≈ full scale.
    const DECOUP_REF = 8.0;

    // RR-quality weight breakpoints (§4.5): w_rr = 1 at artifact_good, 0 at gate.
    const ARTIFACT_GOOD = 1.0;    // <=1% artifact -> full RR weight
}
