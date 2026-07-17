using Toybox.Lang;

//! Fixed-capacity ring buffer of Numbers/Floats. Bounds memory on-device so the
//! rolling windows (30 s NP, 10 min EF, 2 min RR) never grow unbounded. O(1) push.
class RingBuffer {
    hidden var buf;
    hidden var cap;
    hidden var head;   // index of next write
    hidden var count;

    function initialize(capacity) {
        // Coerce to a positive integer (#16). Degenerate inputs (0, negative,
        // fractional, null, or a non-numeric value) collapse to a single slot so
        // the modulo / index math in push/latest/toArray stays well-defined and
        // never divides by zero or indexes an empty array. cap is immutable after
        // construction, so clamping once here is sufficient.
        var n = (capacity != null && capacity has :toNumber) ? capacity.toNumber() : null;
        cap = (n != null && n > 0) ? n : 1;
        buf = new [cap];
        head = 0;
        count = 0;
    }

    //! Push v; returns the evicted (overwritten) value when the buffer was full,
    //! else null. Lets callers maintain O(1) running sums over the window.
    function push(v) {
        var evicted = null;
        if (count == cap) { evicted = buf[head]; }
        buf[head] = v;
        head = (head + 1) % cap;
        if (count < cap) { count++; }
        return evicted;
    }

    function size() { return count; }
    function isFull() { return count == cap; }
    function capacity() { return cap; }

    function clear() { head = 0; count = 0; }

    //! Oldest-to-newest copy as a plain Array (for pure-function math).
    function toArray() {
        var out = new [count];
        var start = (count < cap) ? 0 : head;
        for (var i = 0; i < count; i++) {
            out[i] = buf[(start + i) % cap];
        }
        return out;
    }

    //! Newest value, or null if empty.
    function latest() {
        if (count == 0) { return null; }
        return buf[(head - 1 + cap) % cap];
    }
}
