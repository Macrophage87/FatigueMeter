using Toybox.Lang;
using Toybox.Application.Storage;
using Toybox.Time;
using Toybox.System;

//! Session Result schema version, in its own module so it is reachable by a
//! module-qualified name (SessionSchema.VERSION) from SessionStore's static
//! helpers AND from the unit tests. A class-scope `const` is NOT accessible via
//! `ClassName.CONST` in Monkey C (the compiler can't find the symbol), so the
//! version lives here instead.
//!
//! CONTRACT — bumping VERSION to N REQUIRES adding a v(N-1)->vN upgrade step in
//! SessionStore.migrate() (and, for a multi-version jump, every intermediate
//! step). isValidRecord demands `_v == VERSION` EXACTLY, so any existing record
//! migrate() does not carry up to the new VERSION is silently dropped on the next
//! load() — i.e. a bump WITHOUT a matching migrate() step wipes the entire ride
//! history. migrate() today only stamps *unversioned* (pre-`_v`) records; it has
//! no version-stepping path yet, so VERSION must not be bumped until that path is
//! added there.
module SessionSchema {
    const VERSION = 1;
}

//! SessionStore — persistent compact Session Results + rolling history (white
//! paper §8.3). Enables the cross-ride comparison view ("feat-of-strength day vs
//! attrition day"). Each append persists the whole history under a single key
//! with one atomic Storage.setValue; on read the history is sanitized (bad
//! elements dropped, unversioned records migrated) so a partially-written or
//! foreign value can never corrupt the in-memory list (#18).
class SessionStore {

    hidden const KEY = "fm_sessions_v1";
    hidden const KEY_BAK = "fm_sessions_v1_bak";   // retired; deleted once on load
    hidden const KEY_ACTIVE = "fm_active_v1";      // in-progress ride snapshot (#17)
    hidden const MAX_HISTORY = 20;
    hidden const MIN_HISTORY = 1;   // shed-until-fits floor: never drop below the just-finished ride (#62)

    hidden var history;      // Array of Session Result dictionaries (newest last)
    hidden var writeFailed;  // true if the most recent append() could not persist
    hidden var shed;         // true if the most recent SUCCESSFUL append() dropped older records to fit (#62)

    function initialize() {
        writeFailed = false;
        shed = false;
        load();
    }

    hidden function load() {
        history = sanitize(read(KEY));
        // KEY_BAK is retired: a single Storage.setValue is atomic under Connect
        // IQ's key-value store (a torn write leaves the OLD value, never a half
        // one), so the old primary+backup dance bought nothing. Delete any legacy
        // backup once so it can't linger as dead storage.
        try { Storage.deleteValue(KEY_BAK); } catch (e) { }
        reconcileActive();   // recover a ride whose onStop never fired (#17)
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

    //! Atomic write with shed-until-fits on a storage-full failure (#62). persist()
    //! is a THIN I/O wrapper (#65): it copies `history`, drives the pure shedWrite()
    //! loop with the real tryWrite() writer, and commits the (possibly shrunk) list
    //! to `history` ONLY on a successful write — so any non-persisting failure leaves
    //! the full in-memory history intact, honoring the invariant append() documents
    //! above. Never throws. `shed` is set true only when a durable write dropped
    //! records. The loop itself now lives in shedWrite() so its commit-on-success /
    //! keep-full-history-on-floor invariants are unit-testable with a fake writer.
    hidden function persist() {
        shed = false;   // reset: a later NON-shedding success must not leak a stale shed==true
        // `as Lang.Array` so the copy is a general Array, not the zero-length
        // `Array[]` the type-checker infers for a bare `[]` literal (which rejects
        // index reads like working[0]).
        var working = [] as Lang.Array;                      // shallow copy of history
        for (var i = 0; i < history.size(); i++) { working.add(history[i]); }

        var res = shedWrite(working, MIN_HISTORY, method(:tryWrite));
        if (res[2] == true) {                                // Boolean status -> plain ==, no Object? method call
            if ((res[1] as Lang.Number) > 0) {               // dropped > 0: commit the shrink on success only
                history = res[0] as Lang.Array;
                shed = true;
            }
            return true;
        }
        System.println("SessionStore: persist failed at floor; kept full history in RAM");
        return false;                                        // floor path: history untouched, shed stays false
    }

    //! Pure shed-until-fits driver (#62/#65). Calls `writer.invoke(work)`; on a
    //! too-big signal (0) sheds the OLDEST element from `work` and retries down to
    //! `floor`. Returns [committedArrayOrNull, dropped, ok(Boolean)]:
    //!   ok==true  -> committed is the (possibly shrunk) array that persisted;
    //!   ok==false -> floor reached without a durable write; committed is null and
    //!                the caller must keep its full in-memory history.
    //! `writer` returns 1 = persisted, 0 = too-big (shed & retry). No I/O, no Storage
    //! — so the commit-on-success / stop-at-floor invariants are (:test)-drivable
    //! with a fake writer (CoverageTests FakeShedWriter), independent of whether the
    //! simulator enforces a storage quota.
    static function shedWrite(work, floor, writer) {
        var dropped = 0;
        // Falsifiable condition + trailing return: a bare while(true) trips
        // "not all code paths return a value".
        while (work.size() > 0) {
            if (writer.invoke(work) == 1) { return [work, dropped, true]; }   // committed (maybe shrunk)
            if (!shouldShed(work.size(), floor)) { break; }  // at floor: stop, don't shed below
            work.remove(work[0]);                            // drop OLDEST, retry smaller
            dropped++;
        }
        return [null, dropped, false];                       // floor hit, nothing persisted
    }

    //! Real-I/O writer injected into shedWrite: one Storage.setValue, reporting
    //! 1 = persisted / 0 = too-big. The catch is deliberately catch-ALL — history
    //! integrity does NOT depend on the exception type (persist()'s working-copy
    //! design makes any non-persisting path a no-op on `history`), so no typed
    //! discriminator is landed. Skipping the shed on a non-storable (serialization)
    //! value is intentionally NOT separable on the simulator (#65): the storage-fill
    //! probe only ever provokes the QUOTA exception, never a serialization one, so
    //! "shed on quota, abort on non-storable" cannot be distinguished there.
    //! Lang.InvalidValueException and Lang.UnexpectedTypeException are both plausible
    //! for the full-store path; confirming the exact class is a one-time MANUAL sim
    //! run on the digest-pinned SDK image (release-checklist item), never a CI gate.
    hidden function tryWrite(work) {
        try { Storage.setValue(KEY, work); return 1; }
        catch (e) { return 0; }
    }

    //! Shed another record only while above the floor. Pure so the floor guard is
    //! (:test)-drivable without Storage (#62).
    static function shouldShed(size, floor) { return size > floor; }

    // ---- In-progress checkpoint + reconcile (issue #17) -------------------
    // A ride's summary (session FIT fields + the one history row) is written
    // only by finalizeSession()->onStop, so an ungraceful stop (battery pull /
    // crash / OS kill) loses it. These persist a durable snapshot of the running
    // summary under a SINGLE dedicated key (never through append(), which would
    // churn the MAX_HISTORY ring), and commit it to history on the next load().

    //! Durable in-progress snapshot: one dict under one key, overwritten in place
    //! (O(1) storage, no history growth). `result` must carry a stable
    //! "sessionToken" so reconcile can dedup it against an already-committed row.
    function checkpoint(result) { try { Storage.setValue(KEY_ACTIVE, result); } catch (e) { } }

    //! Drop the in-progress snapshot (graceful stop committed the real row).
    function clearActive() { try { Storage.deleteValue(KEY_ACTIVE); } catch (e) { } }

    //! If a prior ride ended ungracefully its last checkpoint is still in Storage.
    //! Commit it once, stamp `recovered`, and clear KEY_ACTIVE ONLY on a durable
    //! write -- a failed persist keeps the slot so the next load() retries, never
    //! deleting the sole surviving copy of a recovered ride (#17). Because the
    //! recovered row is add()-ed LAST, persist()'s shed-until-fits (#62) drops
    //! oldest history first and structurally protects it, returning false only at
    //! the MIN_HISTORY floor. Decision is the pure shouldRecover() seam; the
    //! sessionToken dedup closes the append->clearActive crash window.
    hidden function reconcileActive() {
        var a = read(KEY_ACTIVE);
        if (shouldRecover(a, history)) {
            var d = a as Lang.Dictionary;
            d.put("recovered", true);   // rebuilt from the last checkpoint (<=1 cadence stale)
            history.add(d);
            while (history.size() > MAX_HISTORY) { history.remove(history[0]); }
            if (persist()) {
                clearActive();          // durably in history -- safe to drop the checkpoint
            } else {
                writeFailed = true;     // surface via lastWriteFailed(); KEY_ACTIVE survives -> retried next load()
            }
        } else {
            clearActive();              // invalid / already-committed / token-less -> drop the stale slot
        }
    }

    //! Pure: recover this snapshot iff it is a valid Session Result carrying a
    //! sessionToken not already committed (#17). isValidRecord already gates the
    //! _v/shape, so a garbage or foreign value is rejected here.
    static function shouldRecover(active, hist) {
        if (!isValidRecord(active)) { return false; }
        var token = (active as Lang.Dictionary)["sessionToken"];
        if (token == null) { return false; }
        return !tokenInHistory(hist, token);
    }

    //! Pure: is `token` already on a committed history row? Scans newest-first.
    static function tokenInHistory(hist, token) {
        for (var i = hist.size() - 1; i >= 0; i--) {
            if ((hist[i] as Lang.Dictionary)["sessionToken"] == token) { return true; }
        }
        return false;
    }

    //! True if the most recent append() could not be persisted to storage.
    function lastWriteFailed() { return writeFailed; }

    //! True if the most recent SUCCESSFUL append() had to shed older records to fit
    //! a full store (the newest ride WAS saved). Mutually exclusive with
    //! lastWriteFailed(); consumed by the #28 "not saved / trimmed" footer.
    function lastWriteShed() { return shed; }

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
    //!
    //! IMPORTANT (see the SessionSchema.VERSION contract): this only handles the
    //! unversioned->current case. When VERSION is bumped, add explicit
    //! v(n)->v(n+1) upgrade steps HERE for every prior version, otherwise
    //! isValidRecord's exact `_v == VERSION` check drops every un-upgraded record
    //! on the next load() and the whole history is lost.
    static function migrate(rec) {
        if (!(rec instanceof Lang.Dictionary)) { return rec; }
        var d = rec as Lang.Dictionary;
        if (!d.hasKey("_v")) { d.put("_v", SessionSchema.VERSION); }
        // (no v(n)->v(n+1) steps needed while VERSION == 1)
        return d;
    }

    //! A record is valid only if it is a dictionary stamped with the current
    //! schema and carrying the two structural keys every Session Result has.
    static function isValidRecord(rec) {
        if (!(rec instanceof Lang.Dictionary)) { return false; }
        var d = rec as Lang.Dictionary;
        if (d["_v"] != SessionSchema.VERSION) { return false; }
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
            "_v" => SessionSchema.VERSION,
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
