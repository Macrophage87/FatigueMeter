using Toybox.Lang;
using Toybox.Test;
using Toybox.Application.Storage;

//! Recovery-boot fixture suite (#113, Tier 1) — the DYNAMIC, storage-backed
//! analogue of the pure SessionStore statics already covered in CoverageTests.
//!
//! WHY THIS SUITE EXISTS. The Critical #109 crash shipped GREEN because every
//! required gate ran against clean-substitute state: CoverageTests drives
//! `shedWrite` through a `FakeShedWriter` (a PUBLIC `write`, bound via explicit
//! receiver), never the production path `persist() -> shedWrite(..., method(:tryWrite))
//! -> writer.invoke -> tryWrite` (SessionStore.mc:113/140/183). A re-`hidden` of
//! `tryWrite` re-ships the UNCATCHABLE "Symbol Not Found / Failed invoking" at the
//! cross-scope `invoke` (SessionStore.mc:164-182). This suite closes that blind
//! spot AND subsumes #111 (the real-`method(:tryWrite)` regression check): each
//! test constructs a REAL `new SessionStore()`, seeded via the real Storage API,
//! driving the full `load -> reconcileActive -> persist -> shedWrite ->
//! method(:tryWrite).invoke` chain end-to-end on the simulator under `monkeydo -t`.
//!
//! HOW A REGRESSION REDDENS THE GATE (fail-closed). The #109-class crash is a
//! VM-level Symbol/System error, NOT a thrown exception — it bypasses every
//! try/catch and aborts the runner (or surfaces as an ERROR row). Either way
//! check_ciq_tests.py reddens (ran != expected, or errors > 0), fail-closed. So
//! for the crash-class fixtures (1, 6) the load-bearing pass signal is simply a
//! CLEAN RETURN past `new SessionStore()`; the boolean asserts then additionally
//! pin that the recovery STATE is correct (count/lastWriteFailed/KEY_ACTIVE
//! cleared-or-retained per the durable-write rule at SessionStore.mc:225-237).
//!
//! STORAGE-IN-(:test) NOTE. No prior in-repo `(:test)` constructs `SessionStore`
//! or touches real `Storage` (CoverageTests only exercises the pure statics), so
//! this suite is also the first confirmation that `Storage.get/setValue` behaves
//! inside a `(:test)` under `monkeydo -t`. High confidence (the harness runs in
//! the real simulator app context, which backs Storage) — but the required
//! `simulate` job is the actual proof. These fixtures deliberately AVOID the
//! non-deterministic full-store/quota path (release-checklist.md:158-159): they
//! seed small values and assert recovery shape, never forcing a write failure.
//!
//! (:test) on the MODULE (#92): makes the ENTIRE module one build-conditional
//! unit so check_test_surface.py Guard 1 passes and the whole surface is stripped
//! from release builds. check_ciq_tests.py tallies only `(:test) function`, so the
//! module tag is count-neutral; each fixture below is a `(:test) function` and is
//! tallied automatically.
(:test)
module RecoveryBootTests {

    // SessionStore's storage keys are `hidden const` (SessionStore.mc:36-39), so
    // they are not reachable by name from here; mirror the exact literals. If a key
    // literal ever changes in SessionStore, update it here too (both are the same
    // on-disk contract).
    const KEY = "fm_sessions_v1";
    const KEY_BAK = "fm_sessions_v1_bak";
    const KEY_ACTIVE = "fm_active_v1";
    const KEY_LAST_OUTCOME = "fm_last_outcome_v1";

    // Hermetic reset: delete EVERY SessionStore key so a fixture never inherits a
    // prior test's (or prior sim-run's) leaked Storage — the sim persists Storage
    // across runs, which is the very leakage #113 calls out. Each `deleteValue` is
    // catch-wrapped: deleting an absent key is a no-op, never a failure.
    function clearAll() {
        try { Storage.deleteValue(KEY); } catch (e) { }
        try { Storage.deleteValue(KEY_BAK); } catch (e) { }
        try { Storage.deleteValue(KEY_ACTIVE); } catch (e) { }
        try { Storage.deleteValue(KEY_LAST_OUTCOME); } catch (e) { }
    }

    // A valid Session Result carrying a sessionToken, in the EXACT shape
    // isValidRecord/shouldRecover demand (_v==VERSION, date, durationS, + token).
    // Built via SessionStore.buildResult so the dict keys track the production
    // schema, not a hand-rolled guess that could be rejected for the wrong reason.
    function validRecord(date, token) {
        var r = SessionStore.buildResult(
            date, 3600, 50.0, 8.0, 42.0,
            0.0, 0.0, 0.0, 0.0,
            0.0, 0.0, 0.0, 0, 0.0,
            "moderate", 5.0);
        r.put("sessionToken", token);
        return r;
    }

    // A full MAX_HISTORY(=20)-row valid history array, tokens 1..20, dates 1..20.
    function fullHistory() {
        var arr = [] as Lang.Array;
        for (var i = 1; i <= 20; i++) { arr.add(validRecord(i, i)); }
        return arr;
    }

    // ---- Fixture 0: empty (all keys absent) — cold-boot control ----
    (:test)
    function testRecoveryBootEmptyStore(logger) {
        clearAll();
        var s = new SessionStore();                 // load: KEY absent -> [] ; no KEY_ACTIVE -> nothing recovered
        var okCount = (s.count() == 0);
        var okNoFail = (s.lastWriteFailed() == false);
        var okOutcome = (s.pendingSaveOutcome() == DescriptiveStrings.SAVE_OK);
        return okCount && okNoFail && okOutcome;
    }

    // ---- Fixture 1: valid in-progress KEY_ACTIVE (fresh token) — the #109 path ----
    (:test)
    function testRecoveryBootRecoversInProgressCheckpoint(logger) {
        // Seeds the ONLY state that reaches the persist->invoke crash site: a valid,
        // uncommitted checkpoint with a fresh sessionToken (shouldRecover true ->
        // reconcileActive persists via method(:tryWrite)). Pre-#109 this reddens the
        // gate (Symbol Not Found aborts construction); post-#109 it returns clean.
        clearAll();
        Storage.setValue(KEY_ACTIVE, validRecord(7, 424242));
        var s = new SessionStore();                 // the full load->reconcile->persist->invoke chain, for real
        var okCount = (s.count() == 1);             // ride recovered into history
        var okNoFail = (s.lastWriteFailed() == false);
        var okCleared = (Storage.getValue(KEY_ACTIVE) == null);   // durable write -> KEY_ACTIVE dropped (SessionStore.mc:231)
        var okOutcome = (s.pendingSaveOutcome() == DescriptiveStrings.SAVE_FAILED);  // recovery this load -> FAILED marker (#83)
        return okCount && okNoFail && okCleared && okOutcome;
    }

    // ---- Fixture 2: corrupt/oversized KEY_ACTIVE (non-dict garbage) ----
    (:test)
    function testRecoveryBootDropsCorruptCheckpoint(logger) {
        // A non-dict checkpoint is rejected by isValidRecord (NOT the #109 crash
        // path — shouldRecover returns false), so reconcileActive just clearActive's
        // the stale slot. No crash, no phantom recovery.
        clearAll();
        Storage.setValue(KEY_ACTIVE, "not-a-dictionary");
        var s = new SessionStore();
        var okCount = (s.count() == 0);             // garbage not recovered
        var okCleared = (Storage.getValue(KEY_ACTIVE) == null);   // stale slot dropped (SessionStore.mc:236)
        var okNoFail = (s.lastWriteFailed() == false);
        return okCount && okCleared && okNoFail;
    }

    // ---- Fixture 3: full valid history (20 rows) under KEY, NO KEY_ACTIVE ----
    (:test)
    function testRecoveryBootLoadsFullHistoryClean(logger) {
        // load() sanitizes a full store; with NO KEY_ACTIVE nothing is recovered or
        // shed (there is no in-progress ride to fold in). Must load all 20 clean.
        clearAll();
        Storage.setValue(KEY, fullHistory());
        var s = new SessionStore();
        var okCount = (s.count() == 20);
        var okNoFail = (s.lastWriteFailed() == false);
        var okOutcome = (s.pendingSaveOutcome() == DescriptiveStrings.SAVE_OK);  // no recovery, no trim
        return okCount && okNoFail && okOutcome;
    }

    // ---- Fixture 4: stale/unversioned + wrong-version records under KEY ----
    (:test)
    function testRecoveryBootMigratesAndDropsLegacy(logger) {
        // One UNVERSIONED record (migrate() stamps _v -> survives) and one
        // WRONG-VERSION record (_v != VERSION -> isValidRecord drops it). Exercises
        // both the migrate and the reject arms of load()'s sanitize with no crash.
        clearAll();
        var arr = [] as Lang.Array;
        arr.add({ "date" => 1, "durationS" => 3600 });          // unversioned -> migrated in
        arr.add({ "_v" => 999, "date" => 2, "durationS" => 60 }); // future/garbage version -> dropped
        Storage.setValue(KEY, arr);
        var s = new SessionStore();
        var okCount = (s.count() == 1);             // only the migrated record survives
        var okNoFail = (s.lastWriteFailed() == false);
        return okCount && okNoFail;
    }

    // ---- Fixture 5: KEY_LAST_OUTCOME="trimmed" — read-once marker ----
    (:test)
    function testRecoveryBootReadsAndClearsTrimMarker(logger) {
        // load() reads the trim marker into trimmedOnLoad, then deletes the key so it
        // never re-shows. pendingSaveOutcome folds it to SAVE_TRIMMED (no recovery).
        clearAll();
        Storage.setValue(KEY_LAST_OUTCOME, "trimmed");
        var s = new SessionStore();
        var okOutcome = (s.pendingSaveOutcome() == DescriptiveStrings.SAVE_TRIMMED);
        var okCleared = (Storage.getValue(KEY_LAST_OUTCOME) == null);   // read-once, key cleared (SessionStore.mc:70)
        var okCount = (s.count() == 0);
        return okOutcome && okCleared && okCount;
    }

    // ---- Fixture 6: combined valid KEY_ACTIVE + full 20-row KEY — #109 worst case ----
    (:test)
    function testRecoveryBootRecoversIntoFullStore(logger) {
        // Recover a ride into an ALREADY-FULL store: reconcileActive add()s the
        // recovered row LAST, the MAX_HISTORY ring sheds the OLDEST, then persist()
        // drives the real method(:tryWrite) writer. Count stays 20, newest is the
        // recovered ride, oldest is shed, KEY_ACTIVE clears on the durable write.
        clearAll();
        Storage.setValue(KEY, fullHistory());                 // tokens 1..20
        Storage.setValue(KEY_ACTIVE, validRecord(99, 999999));  // fresh token, not in history
        var s = new SessionStore();
        var okCount = (s.count() == 20);            // full ring: recovered in, oldest shed
        var okNoFail = (s.lastWriteFailed() == false);
        var okCleared = (Storage.getValue(KEY_ACTIVE) == null);
        var latest = s.latest() as Lang.Dictionary;
        var okNewest = (latest["sessionToken"] == 999999);   // recovered ride is newest
        var okRecovered = (latest["recovered"] == true);     // stamped by reconcileActive (SessionStore.mc:227)
        return okCount && okNoFail && okCleared && okNewest && okRecovered;
    }

    // ---- Fixture 7: recovered checkpoint AT the attempt cap — marker suppressed, ride still kept (#112) ----
    (:test)
    function testRecoveryBootSuppressesMarkerAtCapButKeepsRide(logger) {
        // #112 non-destructive convergence, exercised in the LIVE reconcileActive
        // path (no persist-failure injection needed — suppression is driven by the
        // seeded attempt count, not by a failing write). Seed a valid, fresh-token
        // checkpoint that ALSO carries recoverAttempts == RECOVER_MARKER_CAP (3),
        // modeling a checkpoint that already nagged the cap number of times. The ride
        // is STILL recovered (count 1, token-identity on the committed row, KEY_ACTIVE
        // cleared on the durable write) but the recurring recovery marker is SUPPRESSED
        // (SAVE_OK, not SAVE_FAILED). This is the deterministic A/B against Fixture 1
        // (attempts 0 -> SAVE_FAILED shown): same recovery, marker bounded, ride never
        // dropped. (The cross-boot best-effort counter-WRITE under a real failing
        // persist is the one part a headless (:test) can't force — release-checklist.)
        clearAll();
        var chk = validRecord(11, 424243);
        chk.put("recoverAttempts", 3);              // == RECOVER_MARKER_CAP -> marker suppressed
        Storage.setValue(KEY_ACTIVE, chk);
        var s = new SessionStore();
        var okCount = (s.count() == 1);
        var latest = s.latest() as Lang.Dictionary;
        var okToken = (latest["sessionToken"] == 424243);       // token-identity: the SAME ride recovered
        var okCleared = (Storage.getValue(KEY_ACTIVE) == null); // durable write succeeded -> slot cleared
        var okSuppressed = (s.pendingSaveOutcome() == DescriptiveStrings.SAVE_OK);  // #112: marker suppressed at cap
        return okCount && okToken && okCleared && okSuppressed;
    }
}
