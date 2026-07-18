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

    // record-message field ids (developer field ids must be unique per app)
    enum {
        FLD_AFI = 0, FLD_F = 1, FLD_DECOUP = 2, FLD_A1 = 3,
        FLD_WBAL = 4, FLD_KJW = 5, FLD_FEAT = 6, FLD_ATTR = 7
    }
    // session-message field ids
    enum {
        SFLD_TSS = 20, SFLD_START_FAT = 21, SFLD_END_FAT = 22,
        SFLD_FAT_ADDED = 23, SFLD_PEAK_AFI = 24, SFLD_RED_FEAT = 25,
        SFLD_RED_ATTR = 26, SFLD_KJW = 27
    }

    hidden var rec;        // dictionary id -> field (record)
    hidden var ses;        // dictionary id -> field (session)
    hidden var ok;

    function initialize(dataField) {
        rec = {};
        ses = {};
        ok = false;
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

    hidden function mkRec(df, id, label, units) {
        try {
            var f = df.createField(label, id, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => units });
            rec[id] = f;
        } catch (e) {
            System.println("FitLogger: record field '" + label + "' unavailable");
        }
    }

    hidden function mkSes(df, id, label, units) {
        try {
            var f = df.createField(label, id, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => units });
            ses[id] = f;
        } catch (e) {
            System.println("FitLogger: session field '" + label + "' unavailable");
        }
    }

    hidden function createRecordFields(df) {
        mkRec(df, FLD_AFI,    "AFI",         "idx");
        mkRec(df, FLD_F,      "F_drift",     "bpm");
        mkRec(df, FLD_DECOUP, "decoupling",  "%");
        mkRec(df, FLD_A1,     "DFA_a1",      "");
        mkRec(df, FLD_WBAL,   "Wbal",        "J");
        mkRec(df, FLD_KJW,    "kJ_weighted", "kJ");
        mkRec(df, FLD_FEAT,   "FeatScore",   "");
        mkRec(df, FLD_ATTR,   "AttritionScore", "");
    }

    hidden function createSessionFields(df) {
        mkSes(df, SFLD_TSS,       "TSS",          "");
        // end_fatigue is the ride-INDUCED cardiovascular drift (acute F from a
        // neutral start). start_fatigue / fatigue_added are intentionally NOT
        // exported: a pre-ride residual can't be computed from ride data (§7
        // revised), and exporting a neutral-0 or ledger-guessed value to Garmin /
        // intervals.icu would duplicate or contradict the authoritative load record.
        mkSes(df, SFLD_END_FAT,   "ride_drift",   "bpm");
        mkSes(df, SFLD_PEAK_AFI,  "peak_AFI",     "idx");
        mkSes(df, SFLD_RED_FEAT,  "red_feat_s",   "s");
        mkSes(df, SFLD_RED_ATTR,  "red_attr_s",   "s");
        mkSes(df, SFLD_KJW,       "durability_kJ","kJ");
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
    function logRecord(afi, f, decoup, a1, wbal, kjw, feat, attr) {
        if (!ok) { return; }
        setRec(FLD_AFI, afi);
        setRec(FLD_F, f);
        setRec(FLD_DECOUP, decoup);
        setRec(FLD_A1, a1);
        setRec(FLD_WBAL, wbal);
        setRec(FLD_KJW, kjw);
        setRec(FLD_FEAT, feat);
        setRec(FLD_ATTR, attr);
    }

    //! Write the session summary developer fields at ride end.
    function logSession(summary) {
        if (!ok) { return; }
        setSes(SFLD_TSS, summary[:tss]);
        setSes(SFLD_END_FAT, summary[:endFatigue]);
        setSes(SFLD_PEAK_AFI, summary[:peakAfi]);
        setSes(SFLD_RED_FEAT, summary[:redFeatS]);
        setSes(SFLD_RED_ATTR, summary[:redAttrS]);
        setSes(SFLD_KJW, summary[:durabilityKj]);
    }
}
