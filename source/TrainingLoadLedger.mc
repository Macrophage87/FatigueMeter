using Toybox.Lang;
using Toybox.Math;
using Toybox.Application.Storage;
using Toybox.Time;
using Toybox.Time.Gregorian;

//! LAYER 3 — Residual training-scale fatigue (white paper §5). Persistent across
//! rides via Application.Storage, written transactionally (primary + backup) so a
//! mid-ride crash cannot corrupt CTL/ATL.
//!
//! Standard, well-behaved bookkeeping: TSS (power) or Banister/Edwards TRIMP (HR);
//! CTL(42d)/ATL(7d) EWMAs; TSB = CTL − ATL. ACWR is OPT-IN and OFF by default
//! (mathematically criticised — Lolli/Impellizzeri); shown only as a plain weekly
//! load-ramp display, never a predictive risk score. A CTL ramp >5–8 pts/week is
//! the preferred over-reach cue.
class TrainingLoadLedger {

    hidden const KEY = "fm_ledger_v1";
    hidden const KEY_BAK = "fm_ledger_v1_bak";

    hidden var cfg;
    hidden var ctlYesterday;
    hidden var atlYesterday;
    hidden var chronic28;       // 28-day EWMA for ACWR (opt-in)
    hidden var acute7;          // 7-day EWMA for ACWR (opt-in)
    hidden var lastDay;         // integer day index of last fold
    hidden var todayTss;        // accumulated TSS folded for lastDay
    hidden var ctlHistory;      // recent daily CTL (for ramp)
    hidden var rmssdHistory;    // last 7 resting RMSSD values

    // live within-ride accumulators
    hidden var trimpAccum;
    hidden var secondsAccum;
    hidden var npSumPow4;
    hidden var npCount;

    function initialize(config) {
        cfg = config;
        load();
        trimpAccum = 0.0;
        secondsAccum = 0;
        npSumPow4 = 0.0;
        npCount = 0;
    }

    function setConfig(config) { cfg = config; }

    // =====================================================================
    //  PURE STATIC MATH (unit-testable)
    // =====================================================================

    static function intensityFactor(np, ftp) {
        return MathUtil.safeDiv(np, ftp, 0.0);
    }

    //! TSS = duration_h · IF² · 100 (white paper §5).
    static function tss(durationSec, np, ftp) {
        var iff = intensityFactor(np, ftp);
        var hours = durationSec / 3600.0;
        return hours * iff * iff * 100.0;
    }

    //! Incremental Banister TRIMP for one second (white paper §5, references.md).
    //! dTRIMP = (dt/60)·HRr·coeff·e^(exp·HRr), HRr = (HR−HRrest)/(HRmax−HRrest).
    //! Female coeff is UNRESOLVED (0.86 vs 0.64) — passed in from a SETTING.
    static function trimpIncrement(hr, hrRest, hrMax, dt, coeff, expo) {
        var span = hrMax - hrRest;
        if (span <= 1.0e-6) { return 0.0; }
        var hrr = (hr - hrRest) / span;
        if (hrr < 0) { hrr = 0; }
        if (hrr > 1.0) { hrr = 1.0; }
        var z = expo * hrr;
        if (z > 60.0) { z = 60.0; }
        return (dt / 60.0) * hrr * coeff * Math.exp(z);
    }

    //! CTL/ATL EWMA fold: new = prev + (load − prev)/tau (white paper §5).
    static function ewmaFold(prev, load, tau) {
        return prev + (load - prev) / tau;
    }

    static function tsbFrom(ctlY, atlY) { return ctlY - atlY; }

    // =====================================================================
    //  WITHIN-RIDE ACCUMULATION
    // =====================================================================

    function update(power, hr) {
        secondsAccum++;
        if (power != null && power >= 0) {
            var p2 = power * power;
            npSumPow4 += p2 * p2;
            npCount++;
        }
        if (hr != null && hr > 0) {
            var coeff = cfg.sexFemale ? cfg.trimpFemaleCoeff : Constants.TRIMP_MALE_COEFF;
            var expo = cfg.sexFemale ? Constants.TRIMP_FEMALE_EXP : Constants.TRIMP_MALE_EXP;
            trimpAccum += trimpIncrement(hr, cfg.hrRest, cfg.hrMax, 1.0, coeff, expo);
        }
    }

    //! Ride NP so far (4th-root of mean power⁴ over the whole ride).
    function rideNp() {
        if (npCount == 0) { return 0.0; }
        var m = npSumPow4 / npCount;
        if (m <= 0) { return 0.0; }
        return Math.pow(m, 0.25);
    }

    //! Ride load with graceful degradation: power-TSS if power present, else
    //! HR-TRIMP (white paper §8.4 — no power → HR-TRIMP keeps the ledger live).
    function rideLoad() {
        if (npCount > secondsAccum / 4) {          // enough power samples
            return tss(secondsAccum, rideNp(), cfg.ftp);
        }
        return trimpAccum;                          // TRIMP fallback
    }

    // =====================================================================
    //  LIVE READOUTS (start-of-ride residual context)
    // =====================================================================

    function ctl() { return ctlYesterday; }
    function atl() { return atlYesterday; }
    function tsb() { return tsbFrom(ctlYesterday, atlYesterday); }

    //! Seed for F(0): converts residual load state to "bpm of pre-existing drift"
    //! (white paper §7). SYNTHESIS, uncited — presented downstream as a COARSE
    //! BUCKET, never a point value.
    //!   F(0) = F_ref·clamp( a·max(0,−TSB)/TSB_scale + b·max(0,−RMSSD_z), 0, 0.6 )
    function seedFatigueBpm() {
        var a = 0.6; var b = 0.4; var tsbScale = 30.0;
        var negTsb = -tsb();
        if (negTsb < 0) { negTsb = 0; }
        var rmssdZ = rmssdDeviationZ();
        var negZ = -rmssdZ;
        if (negZ < 0) { negZ = 0; }
        var frac = MathUtil.clamp(a * negTsb / tsbScale + b * negZ, 0.0, 0.6);
        return cfg.fRef * frac;
    }

    //! Coarse start-of-ride bucket (white paper §7): fresh / moderate / heavy.
    function startBucket() {
        var t = tsb();
        if (t > cfg.tsbFresh) { return "fresh"; }
        if (t < cfg.tsbOverreach) { return "heavy"; }
        return "moderate";
    }

    // =====================================================================
    //  RMSSD baseline (personal 7-day ±1 SD — white paper §5)
    // =====================================================================

    function pushRestingRmssd(rmssd) {
        if (rmssd == null || rmssd <= 0) { return; }
        rmssdHistory.add(rmssd);
        while (rmssdHistory.size() > 7) { rmssdHistory.remove(rmssdHistory[0]); }
        save();
    }

    //! z of the latest RMSSD vs the personal 7-day baseline. 0 if <2 samples.
    function rmssdDeviationZ() {
        if (rmssdHistory.size() < 2) { return 0.0; }
        var m = MathUtil.mean(rmssdHistory);
        var sd = MathUtil.stdev(rmssdHistory);
        if (sd < 1.0e-6) { return 0.0; }
        var latest = rmssdHistory[rmssdHistory.size() - 1];
        return (latest - m) / sd;
    }

    // =====================================================================
    //  ACWR (opt-in, descriptive only) & CTL ramp
    // =====================================================================

    function acwr() {
        if (!cfg.acwrEnabled) { return null; }       // OFF by default
        if (chronic28 <= 1.0e-6) { return null; }
        return acute7 / chronic28;
    }

    //! Weekly CTL ramp (preferred over-reach cue). null until enough history.
    function ctlRampPerWeek() {
        if (ctlHistory.size() < 8) { return null; }
        var now = ctlHistory[ctlHistory.size() - 1];
        var weekAgo = ctlHistory[ctlHistory.size() - 8];
        return now - weekAgo;
    }

    // =====================================================================
    //  END-OF-RIDE FOLD (idempotent per day; transactional persist)
    // =====================================================================

    //! Fold the ride's load into the ledger and return the updated CTL/ATL/TSB.
    //! Idempotent per calendar day: multiple rides the same day SUM their TSS and
    //! recompute today's values from yesterday's (no double-application).
    function finalizeRide() {
        var load = rideLoad();
        var day = dayIndex();

        if (day != lastDay) {
            // new day: yesterday's stored values already reflect prior days'
            // EWMA; carry them forward (missed days decay handled at load()).
            lastDay = day;
            todayTss = 0.0;
        }
        todayTss += load;

        var ctlToday = ewmaFold(ctlYesterday, todayTss, Constants.CTL_TAU);
        var atlToday = ewmaFold(atlYesterday, todayTss, Constants.ATL_TAU);

        // shift: today's become the new "yesterday" baseline for the next ride
        ctlYesterday = ctlToday;
        atlYesterday = atlToday;

        if (cfg.acwrEnabled) {
            acute7 = ewmaFold(acute7, todayTss, 7.0);
            chronic28 = ewmaFold(chronic28, todayTss, 28.0);
        }

        ctlHistory.add(ctlToday);
        while (ctlHistory.size() > 60) { ctlHistory.remove(ctlHistory[0]); }

        save();
        return { :ctl => ctlToday, :atl => atlToday, :tsb => tsbFrom(ctlToday, atlToday),
                 :load => load };
    }

    // =====================================================================
    //  PERSISTENCE (transactional)
    // =====================================================================

    hidden function dayIndex() {
        var now = Time.now();
        return (now.value() / 86400).toNumber();
    }
    function dayIndexPublic() { return dayIndex(); }

    hidden function load() {
        var d = readKey(KEY);
        if (d == null || !isValid(d)) { d = readKey(KEY_BAK); }
        if (d == null || !isValid(d)) {
            // cold start from athlete profile seeds
            ctlYesterday = cfg.ctlSeed;
            atlYesterday = cfg.atlSeed;
            chronic28 = cfg.ctlSeed;
            acute7 = cfg.atlSeed;
            lastDay = dayIndex();
            todayTss = 0.0;
            ctlHistory = [cfg.ctlSeed];
            rmssdHistory = [];
            return;
        }
        ctlYesterday = d["ctl"];
        atlYesterday = d["atl"];
        chronic28 = d.hasKey("chronic28") ? d["chronic28"] : cfg.ctlSeed;
        acute7 = d.hasKey("acute7") ? d["acute7"] : cfg.atlSeed;
        lastDay = d["lastDay"];
        todayTss = d["todayTss"];
        ctlHistory = d.hasKey("ctlHistory") ? d["ctlHistory"] : [ctlYesterday];
        rmssdHistory = d.hasKey("rmssd") ? d["rmssd"] : [];

        // decay for any full days missed since the last fold (EWMA relaxes toward 0)
        var today = dayIndex();
        var missed = today - lastDay;
        if (missed > 0 && missed < 400) {
            for (var i = 0; i < missed; i++) {
                ctlYesterday = ewmaFold(ctlYesterday, 0.0, Constants.CTL_TAU);
                atlYesterday = ewmaFold(atlYesterday, 0.0, Constants.ATL_TAU);
            }
            lastDay = today;
            todayTss = 0.0;
        }
    }

    hidden function isValid(d) {
        if (!(d instanceof Lang.Dictionary)) { return false; }
        if (!d.hasKey("ctl") || !d.hasKey("atl") || !d.hasKey("lastDay")
            || !d.hasKey("todayTss")) { return false; }
        return MathUtil.isFinite(d["ctl"]) && MathUtil.isFinite(d["atl"]);
    }

    hidden function readKey(key) {
        try { return Storage.getValue(key); } catch (e) { return null; }
    }

    //! Transactional save: write the new value to the BACKUP key first, then to
    //! the primary. A crash between the two leaves at least one intact copy that
    //! load() validates and prefers.
    hidden function save() {
        var d = { "ctl" => ctlYesterday, "atl" => atlYesterday,
                  "chronic28" => chronic28, "acute7" => acute7,
                  "lastDay" => lastDay, "todayTss" => todayTss,
                  "ctlHistory" => ctlHistory, "rmssd" => rmssdHistory };
        try {
            Storage.setValue(KEY_BAK, d);
            Storage.setValue(KEY, d);
        } catch (e) {
            // out of space / storage error: never let it escape into compute()
        }
    }
}
