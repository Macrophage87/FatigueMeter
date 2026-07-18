using Toybox.Lang;
using Toybox.FitContributor;
using Toybox.System;

//! FitLogger — in-ride time series + session summary via the Connect IQ
//! FitContributor API (white paper §8.3). Record-message developer fields flow
//! into the .FIT and sync to Garmin Connect / intervals.icu; session-message
//! fields carry the ride summary.
//!
//! Every field creation is guarded: if the FitContributor permission is missing
//! or the device rejects a field, logging degrades silently and never blocks the
//! compute loop (white paper §8.4).
class FitLogger {

    // record-message developer field ids (must be unique per app AMONG registered
    // fields). #136 Build 1 (Option B) registers only FLD_AFI..FLD_WBAL (ids 0-4);
    // FLD_KJW/FLD_FEAT/FLD_ATTR are DEFERRED to Build 2 (not registered here), so
    // their ids carry no live FIT field yet — FLD_KJW's value (5) is therefore free
    // for the Build-1 TSS session probe below.
    enum {
        FLD_AFI = 0, FLD_F = 1, FLD_DECOUP = 2, FLD_A1 = 3,
        FLD_WBAL = 4, FLD_KJW = 5, FLD_FEAT = 6, FLD_ATTR = 7
    }
    // session-message developer field ids. #136 Build 1 registers ONLY SFLD_TSS,
    // renumbered 20 -> 5 so every Build-1 field sits in the low 0-5 id range: the
    // id-cap hypothesis (`fieldId < N`) is unrefuted, so all registered ids must be
    // low. id 5 is unused among Build-1's registered fields (FLD_KJW at 5 is
    // deferred/uncreated). The rest are deferred to Build 2 and keep placeholder ids.
    enum {
        SFLD_TSS = 5, SFLD_START_FAT = 21, SFLD_END_FAT = 22,
        SFLD_FAT_ADDED = 23, SFLD_PEAK_AFI = 24, SFLD_RED_FEAT = 25,
        SFLD_RED_ATTR = 26, SFLD_KJW = 27
    }

    hidden var rec;        // dictionary id -> field (record)
    hidden var ses;        // dictionary id -> field (session)
    hidden var ok;
    hidden var nFields;    // #136: global createField-attempt ordinal (FM_FLD diag)

    function initialize(dataField) {
        rec = {};
        ses = {};
        ok = false;
        nFields = 0;   // #136: reset the FM_FLD ordinal per DataField instance
        // #130: FitContributor.createField() is a permission-linked method. On a
        // binary where FitContributor is not *effective* (e.g. the entitlement was
        // not baked into the packaged/signed .prg), createField is not bound as an
        // invocable symbol and calling it raises an UNCATCHABLE `System Error:
        // 'Failed invoking '` that bricks the field -- bypassing every try/catch, in
        // ANY lifecycle phase (the #116/#117 "init-only" theory was falsified
        // on-device, #130). `has` RESOLVES WITHOUT INVOKING, so it is safe on the
        // render-critical path: if `createField` can't resolve we never call it,
        // `ok` stays false, and the field renders its §8.4 NODATA baseline with FIT
        // logging disabled (surfaced by the footer "FIT logging unavailable" marker).
        var hasCreate = (dataField has :createField);
        // #130 Part B diagnostic -- owner reads CIQ_LOG on the Edge 1050 (FW 31.33 /
        // CIQ 6.0.2) to CONFIRM the mechanism; safe to keep, removable once confirmed:
        //   create=false          -> symbol not linked (FitContributor not effective
        //                            -> a build/entitlement fix, not source logic).
        //   create=true but a field still aborts -> linked-but-aborts (entitlement
        //                            not effective at invoke) or a bad field def.
        System.println("FM_CAP fitc=" + (Toybox has :FitContributor)
                       + " create=" + hasCreate);
        if (Toybox has :FitContributor) {
            System.println("FM_CAP tfloat=" + (FitContributor has :DATA_TYPE_FLOAT)
                           + " mrec=" + (FitContributor has :MESG_TYPE_RECORD));
        }
        if (!hasCreate) {
            // Render-survival path: never invoke an unresolvable symbol. FIT logging
            // stays disabled (`ok` false via deriveOk on empty dicts); the field
            // renders. The remedy for the symbol-absent cause is a build/entitlement
            // rebuild+resign (#130), not more source guarding.
            System.println("FitLogger: createField unavailable; FIT logging disabled, field still renders (#130)");
            ok = deriveOk(rec.size(), ses.size());
            return;
        }
        try {
            createRecordFields(dataField);
            createSessionFields(dataField);
        } catch (e) {
            System.println("FitLogger: field creation aborted; logging degraded");
        }
        // Derive availability from what was actually created, not from an
        // exception-free run: mkRec/mkSes swallow their own createField failures
        // (a single rejected field must not abort the rest), so a partial success
        // has to keep logging enabled for the fields that did register. Deriving
        // from the dict sizes makes that rule honest and unit-testable (#20).
        ok = deriveOk(rec.size(), ses.size());
    }

    //! Logging is available if at least one developer field — record or session —
    //! was created. Pure so the partial-success rule is (:test)-drivable without
    //! a real DataField (#20).
    static function deriveOk(recSize, sesSize) {
        return (recSize > 0) || (sesSize > 0);
    }

    //! #130: true iff FIT developer-field logging is live (at least one field was
    //! created). False when the createField capability was absent (guarded off) or
    //! every field was rejected — the view surfaces this as a "FIT logging
    //! unavailable" footer marker so silent ride-data loss is visible.
    function loggingAvailable() { return ok; }

    // #136 diagnostic: the device aborts UNCATCHABLY on the Nth registered
    // developer field (root cause #136). Each mk* logs `FM_FLD try #<ord> id=<id>
    // <TYPE> '<label>'` BEFORE the createField and `FM_FLD ok ...` AFTER it returns.
    // On the uncatchable abort the `try` line prints but the `ok` line never does,
    // and no further `try` line follows — so a fresh CIQ_LOG pins the exact aborting
    // ordinal, fieldId, and message type (the three variables Build 2 must separate:
    // count-cap vs id-cap vs per-type). A CATCHABLE rejection instead prints the
    // "unavailable" line and execution continues to the next field.
    hidden function mkRec(df, id, label, units) {
        nFields++;
        System.println("FM_FLD try #" + nFields + " id=" + id + " REC '" + label + "'");
        try {
            var f = df.createField(label, id, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => units });
            rec[id] = f;
            System.println("FM_FLD ok  #" + nFields + " id=" + id + " '" + label + "'");
        } catch (e) {
            System.println("FitLogger: record field '" + label + "' unavailable");
        }
    }

    hidden function mkSes(df, id, label, units) {
        nFields++;
        System.println("FM_FLD try #" + nFields + " id=" + id + " SES '" + label + "'");
        try {
            var f = df.createField(label, id, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => units });
            ses[id] = f;
            System.println("FM_FLD ok  #" + nFields + " id=" + id + " '" + label + "'");
        } catch (e) {
            System.println("FitLogger: session field '" + label + "' unavailable");
        }
    }

    // #136 Build 1 (Option B): register only 5 record fields (ids 0-4). kJ_weighted
    // (5), FeatScore (6) and AttritionScore (7) are DEFERRED to Build 2 — the device
    // aborts uncatchably on the 7th registered developer field (root cause #136), so
    // Build 1 stays at 6 total (5 record + 1 session) to GUARANTEE a rendered frame
    // (6 registrations are already observed on-device) while the FM_FLD log pins the
    // cap model. Feat/Attrition are `docs/traceability.md`-flagged off the advisory
    // critical path; on-device red-typing (EffortCharacterizer) is unaffected — only
    // their FIT export pauses. Build 2 grows the set back once the cap is measured.
    hidden function createRecordFields(df) {
        mkRec(df, FLD_AFI,    "AFI",         "idx");
        mkRec(df, FLD_F,      "F_drift",     "bpm");
        mkRec(df, FLD_DECOUP, "decoupling",  "%");
        mkRec(df, FLD_A1,     "DFA_a1",      "");
        mkRec(df, FLD_WBAL,   "Wbal",        "J");
    }

    // #136 Build 1: register only TSS, at low id 5 (see enum note) — the render-safe
    // "low-id session field" probe. If it registers, a session-message field works
    // at a low id, so the constraint is not per-type session-specialness. ride_drift
    // / peak_AFI / red_feat_s / red_attr_s / durability_kJ are DEFERRED to Build 2.
    // (start_fatigue / fatigue_added stay intentionally unexported per §7, as before.)
    hidden function createSessionFields(df) {
        mkSes(df, SFLD_TSS, "TSS", "");
    }

    hidden function setRec(id, v) {
        if (rec.hasKey(id) && v != null && MathUtil.isFinite(v)) {
            try { rec[id].setData(v.toFloat()); } catch (e) { }
        }
    }
    hidden function setSes(id, v) {
        if (ses.hasKey(id) && v != null && MathUtil.isFinite(v)) {
            try { ses[id].setData(v.toFloat()); } catch (e) { }
        }
    }

    //! Log one record (called at ~1 Hz from compute()). A null/non-finite input
    //! leaves that field unset for this record; under the FitContributor
    //! developer-field encoding an unset field carries its previous value
    //! forward, so a dropped sensor reads as a held (flat) value rather than a
    //! true gap (see issue #20). A missing sensor never blocks logging of the
    //! other fields.
    // Signature is unchanged from the full field set: setRec gates on
    // `rec.hasKey(id)`, so the #136 Build-1 deferred fields (FLD_KJW/FEAT/ATTR, not
    // registered) simply no-op here — no caller change at FatigueMeterView.
    function logRecord(afi, f, decoup, a1, wbal, kjw, feat, attr) {
        if (!ok) { return; }
        setRec(FLD_AFI, afi);
        setRec(FLD_F, f);
        setRec(FLD_DECOUP, decoup);
        setRec(FLD_A1, a1);
        setRec(FLD_WBAL, wbal);
        setRec(FLD_KJW, kjw);      // #136 Build 1: deferred field, setRec no-ops
        setRec(FLD_FEAT, feat);    // #136 Build 1: deferred field, setRec no-ops
        setRec(FLD_ATTR, attr);    // #136 Build 1: deferred field, setRec no-ops
    }

    //! Write the session summary developer fields at ride end. As with logRecord,
    //! setSes gates on `ses.hasKey(id)`, so the #136 Build-1 deferred session fields
    //! (only TSS is registered) no-op — signature and caller are unchanged.
    function logSession(summary) {
        if (!ok) { return; }
        setSes(SFLD_TSS, summary[:tss]);
        setSes(SFLD_END_FAT, summary[:endFatigue]);   // #136 Build 1: deferred, no-ops
        setSes(SFLD_PEAK_AFI, summary[:peakAfi]);      // #136 Build 1: deferred, no-ops
        setSes(SFLD_RED_FEAT, summary[:redFeatS]);     // #136 Build 1: deferred, no-ops
        setSes(SFLD_RED_ATTR, summary[:redAttrS]);     // #136 Build 1: deferred, no-ops
        setSes(SFLD_KJW, summary[:durabilityKj]);      // #136 Build 1: deferred, no-ops
    }
}
