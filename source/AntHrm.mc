using Toybox.Ant;
using Toybox.Lang;
using Toybox.System;   // System.getTimer(): monotonic ms-since-boot staleness clock

//! ANT+ Heart Rate Monitor RR-interval reader for a DATA FIELD.
//!
//! A data field cannot use Sensor.registerSensorDataListener (that API is
//! Watch-App / Widget only and raises an uncatchable "not available to Data
//! Field" crash). So — exactly like the alphaHRV DFA-α1 field — we open a RAW
//! ANT+ channel to the heart-rate strap and reconstruct beat-to-beat RR
//! intervals from the HRM broadcast data pages.
//!
//! RX-only on the ANT+ managed network, so it coexists with the head unit's
//! native HR recording and with any other RR field: ANT+ is a broadcast
//! profile, so multiple receivers can listen to the same strap.
//!
//! Requires <iq:uses-permission id="Ant"/>. Needs an ANT+ HR strap (Polar H10
//! class). BLE-only straps are not reachable this way; without a strap the
//! channel simply never delivers data and the app runs decoupling-only (§8.4).
class AntHrm extends Ant.GenericChannel {

    // ANT+ HRM device profile
    hidden const DEVICE_TYPE = 120;    // 0x78 = Heart Rate Monitor
    hidden const PERIOD      = 8070;   // 4.06 Hz message period
    hidden const RF_FREQ     = 57;     // 2457 MHz (ANT+)

    hidden var opened;
    hidden var closing;         // true while deliberately releasing -> suppress auto-reopen (#47)
    hidden var rr;              // buffered RR intervals (ms) since last drain
    hidden var havePrev;
    hidden var prevTime;        // last heart-beat event time (1/1024 s)
    hidden var prevCount;       // last heart-beat count (rolls at 256)
    hidden var lastHr;          // last VALID HR (bpm); 0 / no-contact is NEVER stored here (#11)
    hidden var hasHr;           // true once a non-zero HR page has been decoded (#11)
    hidden var lastHrMs;        // System.getTimer() at the last VALID HR page (staleness clock, #11)
    hidden var lastPageMs;      // System.getTimer() of the last DECODED page (stall-watchdog key, #24)
    hidden var decodeErrors;    // latched count of swallowed decode/callback failures (#24)

    function initialize() {
        var assign = new Ant.ChannelAssignment(Ant.CHANNEL_TYPE_RX_ONLY, Ant.NETWORK_PLUS);
        GenericChannel.initialize(method(:onAntMessage), assign);
        rr = [];
        havePrev = false;
        prevTime = 0;
        prevCount = 0;
        lastHr = 0;
        hasHr = false;
        lastHrMs = -1;
        lastPageMs = System.getTimer();   // seed so stallExpired() never does null arithmetic (#24)
        decodeErrors = 0;
        opened = false;
        closing = false;

        var cfg = new Ant.DeviceConfig({
            :deviceNumber => 0,                 // wildcard: pair with any HRM
            :deviceType => DEVICE_TYPE,
            :transmissionType => 0,             // wildcard
            :messagePeriod => PERIOD,
            :radioFrequency => RF_FREQ,
            :searchTimeoutLowPriority => 12,    // ~30 s low-priority search
            :searchThreshold => 0
        });
        GenericChannel.setDeviceConfig(cfg);
    }

    //! Open the channel. Returns true on success. Never throws to the caller.
    function start() {
        closing = false;                 // a fresh open cancels any prior teardown intent
        havePrev = false;                // never bridge beat state across an open (#24)
        try { opened = GenericChannel.open(); } catch (e) { opened = false; }
        lastPageMs = System.getTimer();  // arm the watchdog from open time (#24)
        return opened;
    }

    //! Release the channel at ride end (#47). GenericChannel.release() is an
    //! Ant-namespace API and IS legal in a Data Field (unlike the Sensor API).
    function stop() {
        closing = true;                  // set BEFORE release so its close event is ignored
        try { GenericChannel.release(); } catch (e) { }
        opened = false;
    }

    function isOpen() { return opened; }

    //! Raw last-VALID HR (bpm), or null if none has ever been seen. NEVER 0 -- a
    //! byte-7==0 (lost-contact) page never overwrites a good value (#11). Callers
    //! must null-check, matching every other HR read in the codebase.
    function heartRate() { return hasHr ? lastHr : null; }

    //! Fault-isolated strap HR as a Metric (§8.4): OK while fresh, STALE while
    //! holding a recent-but-aging value, UNAVAILABLE when never seen or long dead.
    //! Pass System.getTimer() as nowMs. Decision logic is the pure Signals
    //! classifier so it stays unit-testable (#11). Consumer wiring is tracked in
    //! the #11 follow-up (#57); AntHrm currently feeds only RR via drainRr().
    function hrMetric(nowMs) {
        var ageMs = (lastHrMs >= 0) ? (nowMs - lastHrMs) : 0x7FFFFFFF;
        var avail = Signals.hrAvailability(hasHr, ageMs,
                        Constants.HR_STALE_S * 1000, Constants.HR_UNAVAIL_S * 1000);
        if (avail == Signals.AVAIL_OK)    { return Signals.Metric.ok(lastHr, 1.0); }
        if (avail == Signals.AVAIL_STALE) { return Signals.Metric.stale(lastHr, "HR stale"); }
        return Signals.Metric.unavailable("no HR");
    }

    //! Return the RR intervals (ms) buffered since the last call, and clear the
    //! buffer. Called once per second by the compute loop.
    function drainRr() {
        // Stall watchdog (#24): RX-fail / search-timeout can wedge the strap WITHOUT
        // emitting CHANNEL_CLOSED. If open but no PAGE has decoded for RR_WATCHDOG_MS
        // (keyed on pages, not RR, so an ectopy/interference channel isn't restarted),
        // force a controlled close+re-open. Window > the ~30 s search so it can't
        // abort acquisition; it does NOT pre-empt the 10 s alpha1 grey.
        if (opened && stallExpired(System.getTimer(), lastPageMs, Constants.RR_WATCHDOG_MS)) {
            watchdogReopen();
        }
        var out = rr;
        rr = [];
        return out;
    }

    //! Has the channel gone silent past the window? Pure so the watchdog gate is
    //! (:test)-drivable without the Ant runtime (#24).
    static function stallExpired(nowMs, lastPageMs, windowMs) {
        return (nowMs - lastPageMs) >= windowMs;
    }

    //! Drop the oldest element once the buffer is at capacity (memory bound for a
    //! stalled compute loop). Pure/(:test)-drivable (#24).
    static function capOldest(arr, max) {
        return (arr.size() >= max) ? arr.slice(1, null) : arr;
    }

    //! EVENT path re-open (a genuine CHANNEL_CLOSED): the stack already closed the
    //! channel, so just re-arm -- no redundant close() (that would raise ANOTHER
    //! CHANNEL_CLOSED). Drops beat state so a gap is never bridged into a fabricated
    //! RR, and refreshes `opened` from open()'s result WITHOUT downgrading it to
    //! false on an already-open no-op (an async CHANNEL_CLOSED from watchdogReopen's
    //! close() can re-enter here after the re-open; open()-on-open returning false
    //! must not stick `opened=false` and silently disable the watchdog, #24).
    hidden function reopenFromEvent() {
        havePrev = false;
        try { if (GenericChannel.open()) { opened = true; } } catch (e) { }
        lastPageMs = System.getTimer();
    }

    //! WATCHDOG path re-open: the channel is open-but-wedged, so close then re-arm.
    //! `closing=true` across the close() suppresses that close()'s SYNCHRONOUS
    //! CHANNEL_CLOSED via shouldReopen; an async one lands on reopenFromEvent() as a
    //! single benign caught open()-on-open (#24).
    hidden function watchdogReopen() {
        closing = true;
        try { GenericChannel.close(); } catch (e) { }
        closing = false;
        reopenFromEvent();
    }

    //! Should a channel-response event trigger the self-heal re-open? True only
    //! for a CHANNEL_CLOSED response received while we are NOT deliberately
    //! releasing (release() raises its own CHANNEL_CLOSED that must be ignored,
    //! #47). Extracted as a PURE static predicate so this decision is (:test)-
    //! drivable without the Ant runtime -- AntHrm itself extends
    //! Ant.GenericChannel and can't be constructed in the pure test harness, the
    //! same reason KalmanMath exposes a (:test) injection seam. Takes raw msgId /
    //! payload / closing so a test can feed synthetic values.
    static function shouldReopen(msgId, payload, closing) {
        if (closing) { return false; }
        if (msgId != Ant.MSG_ID_CHANNEL_RESPONSE_EVENT) { return false; }
        return payload != null && payload.size() >= 2
            && payload[1] == Ant.MSG_CODE_EVENT_CHANNEL_CLOSED;
    }

    //! ANT message callback. Broadcast data pages carry the beat time/count we
    //! reconstruct RR from; channel events (close/search-timeout) trigger a
    //! re-open so a brief dropout self-heals. Guarded so a bad packet is inert.
    function onAntMessage(msg as Toybox.Ant.Message) as Void {
        try {
            var id = msg.messageId;
            if (id == Ant.MSG_ID_BROADCAST_DATA) {
                decode(msg.getPayload());
            } else if (shouldReopen(id, msg.getPayload(), closing)) {
                // Self-heal a dropout by re-opening. shouldReopen() already
                // excludes a deliberate release()'s own close event (#47); the
                // event-path re-open drops beat state + refreshes `opened` (#24).
                reopenFromEvent();
            }
        } catch (e) {
            decodeErrors++;   // latch a persistent fault instead of hiding it (#24)
        }
    }

    //! Latched count of swallowed decode/callback failures (telemetry, #24).
    function decodeErrorCount() { return decodeErrors; }

    //! Decode one HRM broadcast page. Bytes 4-5 = heart-beat event time (1/1024 s,
    //! rolls at 65536); byte 6 = heart-beat count (rolls at 256); byte 7 = HR.
    //! One new RR is emitted each time the beat count advances by exactly 1; a
    //! larger jump means missed beat(s), so we skip it (a gap the DFA artifact
    //! gate handles) rather than fabricate an interval.
    hidden function decode(d) {
        if (d == null || d.size() < 8) { return; }
        lastPageMs = System.getTimer();   // watchdog key: a valid page arrived (#24)
        // A decoded page is proof the channel is open and receiving; refresh `opened`
        // so a transient stuck-false (async double-open, #24) self-corrects. Gated on
        // !closing so a stray queued page can't resurrect a channel after stop().
        if (!closing) { opened = true; }
        // Byte 7 == 0 means loss of skin contact / no reading: never let it
        // overwrite a good HR, and never surface it as a usable value (#11). RR
        // reconstruction (bytes 4/5/6) is independent of byte 7 and unaffected.
        if (Signals.hrByteValid(d[7])) {
            lastHr = d[7] & 0xFF;
            hasHr = true;
            lastHrMs = System.getTimer();
        }
        var beatTime = (d[4] & 0xFF) | ((d[5] & 0xFF) << 8);
        var beatCount = d[6] & 0xFF;
        if (!havePrev) {
            prevTime = beatTime;
            prevCount = beatCount;
            havePrev = true;
            return;
        }
        var res = rrDelta(prevTime, prevCount, beatTime, beatCount);
        if (res[0] == 0) { return; }                   // DUP: keep baseline, no RR
        if (res[0] == 2) { havePrev = false; return; } // RESYNC: reorder/huge gap -> rebaseline next page
        if (res[1] != null) {                          // ADVANCE: emit iff a plausible RR
            rr = capOldest(rr, Constants.RR_BUF_MAX);
            rr.add(res[1]);
        }
        prevTime = beatTime;                           // advance forward only
        prevCount = beatCount;
    }

    //! Pure beat-count/time classifier (extracted so the wrap arithmetic is
    //! (:test)-drivable without the Ant runtime, #24). Returns [action, rrMs]:
    //!   0 DUP     (dCount==0)                 keep baseline, no RR
    //!   1 ADVANCE (1 <= dCount < RR_FWD_MAX)  move baseline forward; rrMs = plausible
    //!                                         RR iff dCount==1 & in-window, else null
    //!   2 RESYNC  (dCount >= RR_FWD_MAX)      reorder OR huge gap -> caller drops the
    //!                                         baseline; never rolls prev* backward
    static function rrDelta(prevTime, prevCount, beatTime, beatCount) {
        var dCount = (beatCount - prevCount) & 0xFF;
        if (dCount == 0) { return [0, null]; }
        if (dCount >= Constants.RR_FWD_MAX) { return [2, null]; }
        var rrMs = null;
        if (dCount == 1) {
            var dt = (beatTime - prevTime) & 0xFFFF;   // 1/1024 s
            var ms = dt * 1000 / 1024;
            if (ms >= 250 && ms <= 2200) { rrMs = ms; }   // 27-240 bpm plausibility
        }
        return [1, rrMs];
    }
}
