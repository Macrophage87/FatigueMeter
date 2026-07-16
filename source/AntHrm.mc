using Toybox.Ant;
using Toybox.Lang;

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
    hidden var lastHr;          // last computed HR (bpm) from the strap

    function initialize() {
        var assign = new Ant.ChannelAssignment(Ant.CHANNEL_TYPE_RX_ONLY, Ant.NETWORK_PLUS);
        GenericChannel.initialize(method(:onAntMessage), assign);
        rr = [];
        havePrev = false;
        prevTime = 0;
        prevCount = 0;
        lastHr = 0;
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
        try { opened = GenericChannel.open(); } catch (e) { opened = false; }
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
    function heartRate() { return lastHr; }

    //! Return the RR intervals (ms) buffered since the last call, and clear the
    //! buffer. Called once per second by the compute loop.
    function drainRr() {
        var out = rr;
        rr = [];
        return out;
    }

    //! ANT message callback. Broadcast data pages carry the beat time/count we
    //! reconstruct RR from; channel events (close/search-timeout) trigger a
    //! re-open so a brief dropout self-heals. Guarded so a bad packet is inert.
    function onAntMessage(msg as Toybox.Ant.Message) as Void {
        try {
            var id = msg.messageId;
            if (id == Ant.MSG_ID_BROADCAST_DATA) {
                decode(msg.getPayload());
            } else if (id == Ant.MSG_ID_CHANNEL_RESPONSE_EVENT) {
                var p = msg.getPayload();
                if (p != null && p.size() >= 2 && p[1] == Ant.MSG_CODE_EVENT_CHANNEL_CLOSED) {
                    // Self-heal a dropout by re-opening -- but NOT during a
                    // deliberate release() (that also raises this close event). (#47)
                    if (!closing) { try { GenericChannel.open(); } catch (e) { } }
                }
            }
        } catch (e) { }
    }

    //! Decode one HRM broadcast page. Bytes 4-5 = heart-beat event time (1/1024 s,
    //! rolls at 65536); byte 6 = heart-beat count (rolls at 256); byte 7 = HR.
    //! One new RR is emitted each time the beat count advances by exactly 1; a
    //! larger jump means missed beat(s), so we skip it (a gap the DFA artifact
    //! gate handles) rather than fabricate an interval.
    hidden function decode(d) {
        if (d == null || d.size() < 8) { return; }
        lastHr = d[7] & 0xFF;
        var beatTime = (d[4] & 0xFF) | ((d[5] & 0xFF) << 8);
        var beatCount = d[6] & 0xFF;
        if (!havePrev) {
            prevTime = beatTime;
            prevCount = beatCount;
            havePrev = true;
            return;
        }
        var dCount = (beatCount - prevCount) & 0xFF;
        if (dCount == 1) {
            var dt = (beatTime - prevTime) & 0xFFFF;   // 1/1024 s
            var ms = dt * 1000 / 1024;
            if (ms >= 250 && ms <= 2200) { rr.add(ms); }   // 27-240 bpm plausibility
        }
        if (dCount >= 1) {
            prevTime = beatTime;
            prevCount = beatCount;
        }
    }
}
