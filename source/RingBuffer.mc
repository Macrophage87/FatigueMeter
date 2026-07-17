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
        // Lazy backbone (#93): start EMPTY and grow to `cap` on push, instead of
        // committing `new [cap]` up front. Cold-start / early-ride heap then tracks
        // ACTUAL fill -- a just-started ride pays for the ~30 samples it holds, not
        // the full 1200-slot 20-min window. Steady-state peak is unchanged (a full
        // ride still reaches `cap`); the win is the construction/first-frame moment
        // (#90's load window) and the tighter-budget devices. All public semantics
        // (push/toArray/latest/size/isFull/capacity/clear) are byte-for-byte
        // identical -- only the allocation TIMING moves.
        buf = [];
        head = 0;
        count = 0;
    }

    //! Push v; returns the evicted (overwritten) value when the buffer was full,
    //! else null. Lets callers maintain O(1) running sums over the window.
    function push(v) {
        var evicted = null;
        if (count == cap) { evicted = buf[head]; }   // full: capture oldest before overwrite
        // Growth invariant: while the buffer is not yet full, head advances
        // 0,1,2,... and wraps to 0 ONLY on the push that makes count == cap, so
        // head == buf.size() throughout the growth phase -> append is always at the
        // end, never a sparse write. Once full (or a slot reused after clear()),
        // head < buf.size() and we overwrite in place.
        if (head < buf.size()) { buf[head] = v; }    // slot exists (full, or post-clear reuse)
        else { buf.add(v); }                          // growth phase: append one slot
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
