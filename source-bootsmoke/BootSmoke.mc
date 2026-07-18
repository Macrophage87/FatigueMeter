using Toybox.Lang;
using Toybox.System;

//! Boot-smoke heartbeat hook — BOOT-SMOKE variant (#124).
//!
//! Selected ONLY by `monkey.bootsmoke.jungle` (sourcePath `source;source-bootsmoke`),
//! used ONLY by the advisory boot-smoke CI job to build the no-`-t` boot binary.
//! Emits one `FM_TICK <n>` line per compute() slice so `scripts/check_boot_smoke.py`
//! can count sustained liveness (a free-running DataField boot that dies uncatchably
//! stops emitting -> the liveness floor fails). This file is NEVER on the shipping
//! sourcePath, so the `FM_TICK` literal cannot reach a release/`-d` artifact.
module BootSmoke {
    function tick(n) { System.println("FM_TICK " + n); }
}
