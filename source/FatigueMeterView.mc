using Toybox.Lang;
using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Activity;
using Toybox.Sensor;
using Toybox.System;

//! The single glance screen + the 1 Hz compute loop (white paper §8.1).
//!
//! compute() keeps the 1 Hz path light and NEVER throws: every calculator is
//! fault-isolated and returns a Signals.Metric, so a missing sensor greys only
//! its own tile (§8.4). The DFA-α1 recompute is budgeted to every 5 s inside the
//! primitives. onUpdate() renders each tile from its own availability.
class FatigueMeterView extends WatchUi.DataField {

    hidden var cfg;
    hidden var prims;
    hidden var filter;
    hidden var effort;
    hidden var ledger;
    hidden var fit;
    hidden var sessions;

    hidden var pendingRr;      // RR intervals (ms) received since last compute
    hidden var tick;           // ride seconds
    hidden var seeded;
    hidden var finalized;

    // ride-summary accumulators
    hidden var startFatigueBpm;
    hidden var peakAfi;
    hidden var lastFreshMatchCount;

    // display snapshot (written by compute, read by onUpdate)
    hidden var dStatus;
    hidden var dAfi;
    hidden var dAfiUnc;
    hidden var dDecoup;
    hidden var dAlpha1;
    hidden var dArtifact;
    hidden var dKjw;
    hidden var dKjTotal;
    hidden var dWmatches;
    hidden var dBest5;
    hidden var dTsb;
    hidden var dStartBucket;
    hidden var dNumericUnlocked;
    hidden var dCalibrated;
    hidden var dSourceSwitched;
    hidden var dPriorDominated;
    hidden var dRedKind;
    hidden var dPowerAvail;
    hidden var dStationary;

    function initialize() {
        DataField.initialize();
        cfg = new Config();
        prims = new PrimitivesCalculator(cfg);
        filter = new AcuteFatigueFilter(cfg);
        effort = new EffortCharacterizer(cfg);
        ledger = new TrainingLoadLedger(cfg);
        sessions = new SessionStore();
        fit = new FitLogger(self);

        pendingRr = [];
        tick = 0;
        seeded = false;
        finalized = false;
        startFatigueBpm = 0.0;
        peakAfi = 0.0;
        lastFreshMatchCount = 0;

        dStatus = { :status => DescriptiveStrings.STATUS_NODATA, :redKind => "none",
                    :advisoryActive => false, :alpha1Gated => true, :decoupOnly => true };
        dAfi = null; dAfiUnc = 100.0;
        dDecoup = Signals.Metric.unavailable("--");
        dAlpha1 = Signals.Metric.unavailable("no RR");
        dArtifact = null;
        dKjw = 0.0; dKjTotal = 0.0; dWmatches = 0;
        dBest5 = 0.0; dTsb = ledger.tsb(); dStartBucket = ledger.startBucket();
        dNumericUnlocked = cfg.numericAfiUnlocked();
        dCalibrated = CalibrationFit.isCalibrated();
        dSourceSwitched = false;
        dPriorDominated = true;
        dRedKind = "none";
        dPowerAvail = false;
        dStationary = false;

        registerSensors();
    }

    function onSettingsChanged() {
        cfg.reload();
        prims.setConfig(cfg);
        filter.setConfig(cfg);
        effort.setConfig(cfg);
        ledger.setConfig(cfg);
        dNumericUnlocked = cfg.numericAfiUnlocked();
    }

    hidden function registerSensors() {
        try {
            Sensor.registerSensorDataListener(method(:onSensorData), {
                :period => 1,
                :heartBeatIntervals => { :enabled => true }
            });
        } catch (e) {
            // RR listener unavailable -> app runs in decoupling-only fallback
        }
    }

    //! Beat-to-beat RR callback. Buffers intervals for the next compute(); guarded
    //! so a malformed packet never disturbs the compute loop.
    function onSensorData(sensorData) {
        try {
            if (sensorData == null) { return; }
            var arr = null;
            // SDK member name has varied; accept either spelling.
            if (sensorData has :heartBeatIntervals && sensorData.heartBeatIntervals != null) {
                arr = sensorData.heartBeatIntervals;
            } else if (sensorData has :heartBeatIntervalData && sensorData.heartBeatIntervalData != null) {
                arr = sensorData.heartBeatIntervalData;
            }
            if (arr != null) {
                for (var i = 0; i < arr.size(); i++) { pendingRr.add(arr[i]); }
            }
        } catch (e) { }
    }

    // =====================================================================
    //  1 Hz COMPUTE
    // =====================================================================

    function compute(info) {
        tick++;

        var power = (info != null) ? sanitize(info.currentPower) : null;
        var hr = (info != null) ? sanitize(info.currentHeartRate) : null;
        var cadence = (info != null) ? sanitize(info.currentCadence) : null;

        var rr = pendingRr;
        pendingRr = [];

        // "active" = actually doing work (pedaling / producing power). Basing this
        // on pedaling rather than HR>rest is what lets F RELAX on coasting/stops
        // (white paper §4.4 goal): during a coast HR can stay high yet no work is
        // done, so κ_d must switch off and F decays via τ_rec.
        var active = (cadence != null && cadence > 0)
                     || (power != null && power > 0.05 * cfg.ftp);
        var stationary = prims.isStationary();
        dStationary = stationary;
        dPowerAvail = (power != null);

        // ---- Layer 1 ----
        prims.update(power, hr, cadence, rr, tick);

        // ---- Layer 3 accumulation ----
        ledger.update(power, hr);

        // ---- seed F(0) from residual state at ride start (§7) ----
        if (!seeded && tick >= 2) {
            startFatigueBpm = ledger.seedFatigueBpm();
            filter.seedFromLayer3(startFatigueBpm);
            seeded = true;
        }

        // ---- α1 expected-for-power (population or calibrated sigmoid) ----
        var a1Metric = prims.alpha1Metric();
        var pForA1 = (power != null) ? power.toFloat() : cfg.pAeT;
        var a1Expected = AcuteFatigueFilter.a1Target(pForA1, cfg.pAeT, cfg.a0, cfg.a1, cfg.sigmoidS);
        var a1Measured = a1Metric.isUsable() ? a1Metric.value : a1Expected;
        var a1DriftBelow = a1Expected - a1Measured;      // >0 when below expected
        if (a1DriftBelow < 0) { a1DriftBelow = 0.0; }

        // ---- Layer 2 filter ----
        filter.step(power, hr, a1Metric, prims.alpha1Artifact(), prims.alpha1Fb(),
                    active, stationary);

        // ---- decoupling + AFI blend ----
        dDecoup = prims.decouplingMetric();
        var decoupVal = dDecoup.isUsable() ? dDecoup.value : 0.0;
        var afi = filter.afiBlended(decoupVal, prims.alpha1Artifact());
        dAfi = afi;
        dAfiUnc = filter.afiUncertainty();
        dSourceSwitched = filter.didSourceSwitch();
        dPriorDominated = filter.isPriorDominated();

        if (afi > peakAfi) { peakAfi = afi; }

        // ---- effort characterizer (off the critical path) ----
        effort.setKjAboveCp(prims.kjAboveCp());
        effort.update(power, prims.wBalFraction(), decoupVal, a1DriftBelow, prims.kjWeightedValue());
        dBest5 = effort.best5();
        dWmatches = effort.matchesBurned();
        var freshMatch = (effort.matchesBurned() > lastFreshMatchCount);
        lastFreshMatchCount = effort.matchesBurned();
        dRedKind = effort.redCharacter(dBest5, a1DriftBelow);

        // ---- status band (per-athlete; Feat/Attrition never gates) ----
        dAlpha1 = a1Metric;
        var artMetric = prims.artifactPercentMetric();
        dArtifact = artMetric.isPresent() ? artMetric.value : null;
        dKjw = prims.kjWeightedValue();
        var kjt = prims.kjTotalMetric();
        dKjTotal = kjt.isPresent() ? kjt.value : 0.0;
        dTsb = ledger.tsb();
        dStartBucket = ledger.startBucket();

        var wRr = AcuteFatigueFilter.rrWeight(prims.alpha1Artifact(),
                     Constants.ARTIFACT_GOOD, cfg.artifactGate);
        var sensorsPresent = (power != null) || (hr != null) || a1Metric.isUsable();

        dStatus = StatusEvaluator.evaluate(cfg, {
            :afi => afi, :decoupMetric => dDecoup, :alpha1Metric => a1Metric,
            :kjWeighted => dKjw, :elapsedS => tick, :wRr => wRr,
            :redKind => dRedKind, :sensorsPresent => sensorsPresent,
            :afiDrift => filter.afiDriftAboveBaseline()
        });

        // ---- time-in-red split (Feat vs Attrition minutes — §8.3) ----
        if (dStatus[:status] == DescriptiveStrings.STATUS_DRIFTING) {
            effort.accrueRedSecond(power, freshMatch);
        }

        // ---- FIT record logging ----
        fit.logRecord(afi, filter.fState(), decoupVal, prims.alpha1Raw(),
                      prims.wBalFraction() * cfg.wPrime, dKjw,
                      effort.feat(dBest5), effort.attrition(a1DriftBelow));
    }

    //! Validate a raw Activity.Info field into a finite number or null. This is
    //! the sensor-read guard (white paper §8.4): a missing/garbage value becomes
    //! null and greys only its dependent tiles.
    hidden function sanitize(v) {
        if (v == null) { return null; }
        if (!(v instanceof Lang.Number || v instanceof Lang.Float
              || v instanceof Lang.Long || v instanceof Lang.Double)) { return null; }
        if (!MathUtil.isFinite(v)) { return null; }
        return v;
    }

    // =====================================================================
    //  SESSION FINALIZE (called from App.onStop — ride ended/saved)
    // =====================================================================

    function finalizeSession() {
        if (finalized) { return; }
        finalized = true;

        var endF = filter.fState();
        var fold = ledger.finalizeRide();
        var added = endF - startFatigueBpm;

        // §7: end-of-ride fatigue and fatigue-added are BUCKETED (differences of
        // soft, weakly-observable estimates), never presented as point bpm on
        // screen. The raw bpm still flow to the FIT session field for export.
        var startBucketLbl = AcuteFatigueFilter.fatigueBucket(startFatigueBpm, cfg.fRef);
        var endBucketLbl = AcuteFatigueFilter.fatigueBucket(endF, cfg.fRef);
        var addedBucketLbl = AcuteFatigueFilter.deltaBucket(added, cfg.fRef);

        var summary = {
            :tss => fold[:load],
            :startFatigue => startFatigueBpm,
            :endFatigue => endF,
            :fatigueAdded => added,
            :peakAfi => peakAfi,
            :redFeatS => effort.redFeatSeconds(),
            :redAttrS => effort.redAttritionSeconds(),
            :durabilityKj => prims.kjWeightedValue()
        };
        fit.logSession(summary);

        var result = SessionStore.buildResult(
            ledger.dayIndexPublic(), tick, fold[:load],
            startFatigueBpm, endF, added, peakAfi,
            effort.redFeatSeconds(), effort.redAttritionSeconds(),
            effort.feat(effort.best5()), effort.attrition(0.0),
            effort.best1(), effort.best5(), effort.best20(),
            effort.matchesBurned(), prims.kjWeightedValue(),
            fold[:ctlEnd], fold[:atlEnd], fold[:startTsb],
            startBucketLbl, endBucketLbl, addedBucketLbl, filter.afiUncertainty());
        sessions.append(result);
    }

    // =====================================================================
    //  RENDER — the single glance screen (§8.1)
    // =====================================================================

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, 0x111111);
        dc.clear();

        // Evidence row is given AT LEAST equal height to the status band (§8.1 —
        // the primitives are the validated part), 0.26·h each.
        drawStatusBand(dc, w, h, 0, (h * 0.26).toNumber());
        drawDial(dc, w, h, (h * 0.26).toNumber(), (h * 0.18).toNumber());
        drawEvidenceRow(dc, w, h, (h * 0.44).toNumber(), (h * 0.26).toNumber());
        drawFeatsStrip(dc, w, h, (h * 0.70).toNumber(), (h * 0.13).toNumber());
        drawFooter(dc, w, h, (h * 0.83).toNumber(), (h * 0.17).toNumber());
    }

    hidden function statusColor(status) {
        switch (status) {
            case DescriptiveStrings.STATUS_FRESH:    return 0x2E9E2E;
            case DescriptiveStrings.STATUS_BUILDING: return 0xD9A400;
            case DescriptiveStrings.STATUS_DRIFTING: return 0xCC2222;
            default:                                 return 0x555555;
        }
    }

    //! 1. Status band (largest) with the persistent advisory/uncalibrated tag.
    hidden function drawStatusBand(dc, w, h, y, bandH) {
        var status = dStatus[:status];
        var col = statusColor(status);
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, y, w, bandH);

        // main label (text + colour — never colour alone)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var label = DescriptiveStrings.statusLabel(status);
        dc.drawText(w / 2, y + bandH * 0.30, Graphics.FONT_LARGE, label,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // second line: red character (Feat/Attrition) — characterization, NOT a command
        if (status == DescriptiveStrings.STATUS_DRIFTING && !dRedKind.equals("none")) {
            var rc = DescriptiveStrings.redCharacterLabel(dRedKind);
            var rcol = dRedKind.equals("feat") ? 0xFFCC33 : Graphics.COLOR_WHITE;
            dc.setColor(rcol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y + bandH * 0.58, Graphics.FONT_MEDIUM, rc,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // persistent honesty tag ON THE BAND itself — the "advisory · not a
        // validated measurement" tag is ALWAYS present (the "uncalibrated" note is
        // shown separately in the footer, not as a replacement for this one).
        var tag = DescriptiveStrings.advisoryTag();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y + bandH * 0.85, Graphics.FONT_XTINY, tag,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! 2. Acute Fatigue dial. Pre-pilot: 3-state band + coarse start/now. Post-
    //! pilot: precise AFI digit + now tick + shaded projection range.
    hidden function drawDial(dc, w, h, y, dialH) {
        var pad = (w * 0.06).toNumber();
        var barY = y + (dialH * 0.45).toNumber();
        var barH = (dialH * 0.22).toNumber();
        var barW = w - 2 * pad;

        // three colour segments (green | amber | red) — always with text markers
        var seg = barW / 3;
        dc.setColor(0x2E9E2E, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(pad, barY, seg, barH);
        dc.setColor(0xD9A400, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(pad + seg, barY, seg, barH);
        dc.setColor(0xCC2222, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(pad + 2 * seg, barY, barW - 2 * seg, barH);

        // coarse "start" marker from the start bucket
        var startPos = bucketToX(dStartBucket, pad, barW);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startPos, barY - barH, Graphics.FONT_XTINY, "S",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (dNumericUnlocked && dAfi != null) {
            // POST-PILOT: precise AFI digit + now tick + projection range
            var nowX = pad + (MathUtil.clamp(dAfi / 100.0, 0.0, 1.0) * barW).toNumber();
            // projection range as a shaded band = now ± uncertainty
            var uncW = (MathUtil.clamp(dAfiUnc / 100.0, 0.0, 1.0) * barW).toNumber();
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(nowX - uncW, barY, 2 * uncW, barH);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(nowX - 1, barY - 2, 3, barH + 4);
            dc.drawText(w / 2, y + (dialH * 0.15).toNumber(), Graphics.FONT_NUMBER_MEDIUM,
                        "AFI " + dAfi.format("%.0f"),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            // PRE-PILOT (default): coarse "now" marker in the active band, no digit
            var nowBucket = statusToBucket(dStatus[:status]);
            var nowX = bucketToX(nowBucket, pad, barW);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(nowX - 2, barY - 4, 5, barH + 8);
            dc.drawText(nowX, barY + barH + 2, Graphics.FONT_XTINY, "NOW",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y + (dialH * 0.12).toNumber(), Graphics.FONT_TINY,
                        "Acute Fatigue (3-state)",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    hidden function statusToBucket(status) {
        if (status == DescriptiveStrings.STATUS_FRESH) { return "fresh"; }
        if (status == DescriptiveStrings.STATUS_BUILDING) { return "moderate"; }
        return "heavy";
    }
    hidden function bucketToX(bucket, pad, barW) {
        var frac = 0.5 / 3.0;                 // green centre
        if (bucket.equals("moderate")) { frac = 1.5 / 3.0; }
        if (bucket.equals("heavy")) { frac = 2.5 / 3.0; }
        return pad + (frac * barW).toNumber();
    }

    //! 3. Evidence row (equal weight to the band — the validated part).
    hidden function drawEvidenceRow(dc, w, h, y, rowH) {
        var cellW = w / 4;
        drawCell(dc, 0, y, cellW, rowH, "DECOUP",
                 fmtMetricPct(dDecoup), metricColor(dDecoup));
        drawCell(dc, cellW, y, cellW, rowH, "DFA-a1",
                 fmtAlpha(dAlpha1), metricColor(dAlpha1));
        drawKjBar(dc, 2 * cellW, y, cellW, rowH);
        // matches (W′bal) is power-dependent — grey with a marker on power loss.
        if (dPowerAvail) {
            drawCell(dc, 3 * cellW, y, cellW, rowH, "MATCHES",
                     dWmatches.format("%d"), Graphics.COLOR_WHITE);
        } else {
            drawCell(dc, 3 * cellW, y, cellW, rowH, "MATCHES", "— no pwr", 0x777777);
        }
    }

    hidden function drawCell(dc, x, y, cw, ch, title, value, valColor) {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + cw / 2, y + ch * 0.20, Graphics.FONT_XTINY, title,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(valColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + cw / 2, y + ch * 0.60, Graphics.FONT_MEDIUM, value,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawKjBar(dc, x, y, cw, ch) {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + cw / 2, y + ch * 0.20, Graphics.FONT_XTINY, "kJ/ANCHOR",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (!dPowerAvail) {
            dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + cw / 2, y + ch * 0.60, Graphics.FONT_MEDIUM, "no power",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var frac = MathUtil.clamp(MathUtil.safeDiv(dKjw, cfg.kjAnchor, 0.0), 0.0, 1.0);
        var bw = (cw * 0.7).toNumber();
        var bx = x + (cw * 0.15).toNumber();
        var by = y + (ch * 0.55).toNumber();
        var bh = (ch * 0.22).toNumber();
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx, by, bw, bh);
        dc.setColor(frac >= 1.0 ? 0xCC2222 : 0x3388CC, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx, by, (bw * frac).toNumber(), bh);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + cw / 2, y + ch * 0.85, Graphics.FONT_XTINY,
                    dKjw.format("%.0f") + "/" + cfg.kjAnchor.format("%.0f"),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! 4. Feats strip: best 5-min power, matches, TSB / start-fatigue context.
    hidden function drawFeatsStrip(dc, w, h, y, rowH) {
        var cellW = w / 3;
        // best-5 is power-dependent: grey with "no power" when the meter is absent.
        if (dPowerAvail) {
            drawCell(dc, 0, y, cellW, rowH, "BEST 5min",
                     dBest5.format("%.0f") + "W", 0xFFCC33);
        } else {
            drawCell(dc, 0, y, cellW, rowH, "BEST 5min", "no power", 0x777777);
        }
        drawCell(dc, cellW, y, cellW, rowH, "TSB",
                 dTsb.format("%.0f"), tsbColor(dTsb));
        drawCell(dc, 2 * cellW, y, cellW, rowH, "START",
                 DescriptiveStrings.startBucketLabel(dStartBucket), Graphics.COLOR_WHITE);
    }

    hidden function tsbColor(tsb) {
        if (tsb < cfg.tsbOverreach) { return 0xCC2222; }
        if (tsb > cfg.tsbFresh) { return 0x2E9E2E; }
        return 0xD9A400;
    }

    //! 5. Data-quality footer: artifact %/α1 validity + stationarity + fallback +
    //! the "uncalibrated" note (when applicable) + the non-medical disclaimer.
    hidden function drawFooter(dc, w, h, y, rowH) {
        dc.setColor(0x1A1A1A, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, y, w, rowH);

        // line 1: RR artifact / α1 validity + steadiness indicator
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y + rowH * 0.16, Graphics.FONT_XTINY, footerText(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // line 2: advisory basis / uncalibrated note
        var line2 = "";
        if (!dCalibrated) {
            line2 = DescriptiveStrings.uncalibratedTag();
        } else if (dStatus[:decoupOnly]) {
            line2 = DescriptiveStrings.decoupOnlyTag();
        } else if (dStatus[:alpha1Gated] && dStatus[:advisoryActive]) {
            line2 = "advisory on decoupling + kJ only (a1 gated) — weighted down";
        } else if (dPriorDominated) {
            line2 = "steady power: AFI prior-dominated";
        }
        if (!line2.equals("")) {
            dc.drawText(w / 2, y + rowH * 0.45, Graphics.FONT_XTINY, line2,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // line 3: persistent non-medical-device disclaimer (white paper §10)
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y + rowH * 0.78, Graphics.FONT_XTINY,
                    DescriptiveStrings.notMedical(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    hidden function footerText() {
        var steady = dStationary ? "steady" : "variable";
        if (dArtifact == null) { return "no RR — decoupling-only  ·  " + steady; }
        var q = "";
        if (dAlpha1 != null && dAlpha1.availability == Signals.AVAIL_OK) {
            q = "a1 ok";
        } else if (dAlpha1 != null && dAlpha1.label != null) {
            q = "a1 " + dAlpha1.label;
        }
        return "RR artifact " + dArtifact.format("%.0f") + "%  ·  " + q + "  ·  " + steady;
    }

    // ---- metric formatting / colours ----
    hidden function metricColor(m) {
        if (m == null || !m.isPresent()) { return 0x777777; }
        if (m.availability == Signals.AVAIL_OK) { return Graphics.COLOR_WHITE; }
        return 0xAAAA55;   // low-confidence / stale
    }
    hidden function fmtMetricPct(m) {
        if (m == null || !m.isPresent()) { return m == null ? "--" : (m.label == null ? "--" : m.label); }
        return m.value.format("%.1f") + "%";
    }
    hidden function fmtAlpha(m) {
        if (m == null || !m.isPresent()) { return "no RR"; }
        return m.value.format("%.2f");
    }
}
