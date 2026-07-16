using Toybox.Lang;
using Toybox.Application.Storage;
using Toybox.Time;
using Toybox.System;

//! SessionStore — persistent compact Session Results + rolling history (white
//! paper §8.3). Enables the cross-ride comparison view ("feat-of-strength day vs
//! attrition day"). Each append persists the whole history under a single key
//! with one atomic Storage.setValue; on read the history is sanitized (bad
//! elements dropped, unversioned records migrated) so a partially-written or
//! foreign value can never corrupt the in-memory list (#18).
class SessionStore {

    //! Session Result schema version. Bumped when buildResult's shape changes;
    //! read-side migrate()/isValidRecord() gate on it so a stale-shaped record is
    //! upgraded or dropped rather than trusted.
    const SCHEMA = 1;

    hidden const KEY = "fm_sessions_v1";
    hidden const KEY_BAK = "fm_sessions_v1_bak";   // retired; deleted once on load
    hidden const MAX_HISTORY = 20;

    hidden var history;      // Array of Session Result dictionaries (newest last)
    hidden var writeFailed;  // true if the most recent append() could not persist

    function initialize() {
        writeFailed = false;
        load();
    }

    hidden function load() {
        history = sanitize(read(KEY));
        // KEY_BAK is retired: a single Storage.setValue is atomic under Connect
        // IQ's key-value store (a torn write leaves the OLD value, never a half
        // one), so the old primary+backup dance bought nothing. Delete any legacy
        // backup once so it can't linger as dead storage.
        try { Storage.deleteValue(KEY_BAK); } catch (e) { }
    }

    hidden function read(key) {
        try { return Storage.getValue(key); } catch (e) { return null; }
    }

    //! Append a Session Result and persist. Returns true on a durable write,
    //! false if persistence failed (the record is still kept in the in-memory
    //! history so the current ride's comparison view stays correct; the failure
    //! is surfaced via lastWriteFailed()). Keeps only the last MAX_HISTORY.
    function append(result) {
        history.add(result);
        while (history.size() > MAX_HISTORY) { history.remove(history[0]); }
        writeFailed = !persist();
        return !writeFailed;
    }

    //! Single atomic write of the whole history. Returns false (never throws) if
    //! storage rejected the write (e.g. full); the caller keeps the in-memory copy.
    hidden function persist() {
        try {
            Storage.setValue(KEY, history);
            return true;
        } catch (e) {
            System.println("SessionStore: persist failed, keeping in-memory history");
            return false;
        }
    }

    //! True if the most recent append() could not be persisted to storage.
    function lastWriteFailed() { return writeFailed; }

    function count() { return history.size(); }
    function all() { return history; }
    function latest() {
        if (history.size() == 0) { return null; }
        return history[history.size() - 1];
    }

    //! Coerce a raw stored value into a clean history array: drop anything that
    //! isn't a valid Session Result, migrating unversioned (legacy) records first.
    //! A non-array or null input yields an empty history.
    static function sanitize(raw) {
        if (!(raw instanceof Lang.Array)) { return []; }
        var arr = raw as Lang.Array;
        var out = [];
        for (var i = 0; i < arr.size(); i++) {
            var rec = migrate(arr[i]);
            if (isValidRecord(rec)) { out.add(rec); }
        }
        return out;
    }

    //! Upgrade a legacy record in place: an unversioned dictionary predates the
    //! "_v" stamp, so treat it as the current schema. Non-dictionaries pass
    //! through unchanged (isValidRecord will reject them).
    static function migrate(rec) {
        if (!(rec instanceof Lang.Dictionary)) { return rec; }
        var d = rec as Lang.Dictionary;
        if (!d.hasKey("_v")) { d.put("_v", SessionStore.SCHEMA); }
        return d;
    }

    //! A record is valid only if it is a dictionary stamped with the current
    //! schema and carrying the two structural keys every Session Result has.
    static function isValidRecord(rec) {
        if (!(rec instanceof Lang.Dictionary)) { return false; }
        var d = rec as Lang.Dictionary;
        if (d["_v"] != SessionStore.SCHEMA) { return false; }
        return d.hasKey("date") && d.hasKey("durationS");
    }

    //! Build a Session Result dictionary (white paper §8.3 fields).
    //!
    //! Ride-scoped, ride-measured quantities only. Pre-ride residual fatigue and
    //! the cross-ride CTL/ATL/TSB are not computable on-device (§7 revised) and are
    //! deliberately absent — `endFatigue` is the ride-INDUCED cardiovascular drift
    //! (acute F from a neutral start), reported as a coarse bucket, never a raw bpm.
    static function buildResult(date, durationS, tss, endFatigue, peakAfi,
                                redFeatS, redAttrS, featScore, attritionScore,
                                best1, best5, best20, matches, durabilityKj,
                                endBucket, fatigueBandPts) {
        return {
            "_v" => SessionStore.SCHEMA,
            "date" => date, "durationS" => durationS, "tss" => tss,
            "endFatigue" => endFatigue, "peakAfi" => peakAfi,
            "endBucket" => endBucket, "fatigueBandPts" => fatigueBandPts,
            "redFeatS" => redFeatS, "redAttrS" => redAttrS,
            "featScore" => featScore, "attritionScore" => attritionScore,
            "best1" => best1, "best5" => best5, "best20" => best20,
            "matches" => matches, "durabilityKj" => durabilityKj
        };
    }
}
