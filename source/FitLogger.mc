using Toybox.Lang;
using Toybox.FitContributor;

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
        try {
            createRecordFields(dataField);
            createSessionFields(dataField);
            ok = true;
        } catch (e) {
            ok = false;   // logging unavailable; app still runs
        }
    }

    hidden function mkRec(df, id, label, units) {
        try {
            var f = df.createField(label, id, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => units });
            rec[id] = f;
        } catch (e) { }
    }

    hidden function mkSes(df, id, label, units) {
        try {
            var f = df.createField(label, id, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => units });
            ses[id] = f;
        } catch (e) { }
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
        mkSes(df, SFLD_START_FAT, "start_fatigue","bpm");
        mkSes(df, SFLD_END_FAT,   "end_fatigue",  "bpm");
        mkSes(df, SFLD_FAT_ADDED, "fatigue_added","bpm");
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

    //! Log one record (called at ~1 Hz from compute()). Any null/absent value is
    //! simply skipped — a missing sensor never blocks logging of the rest.
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
        setSes(SFLD_START_FAT, summary[:startFatigue]);
        setSes(SFLD_END_FAT, summary[:endFatigue]);
        setSes(SFLD_FAT_ADDED, summary[:fatigueAdded]);
        setSes(SFLD_PEAK_AFI, summary[:peakAfi]);
        setSes(SFLD_RED_FEAT, summary[:redFeatS]);
        setSes(SFLD_RED_ATTR, summary[:redAttrS]);
        setSes(SFLD_KJW, summary[:durabilityKj]);
    }
}
