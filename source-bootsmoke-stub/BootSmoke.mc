using Toybox.Lang;

//! Boot-smoke heartbeat hook — SHIPPING no-op variant (#124).
//!
//! FatigueMeterView.compute() calls `BootSmoke.tick(n)` unconditionally every
//! 1 Hz slice. In EVERY normal build (`monkey.jungle` -> sourcePath includes
//! THIS dir, `source-bootsmoke-stub`) it resolves to this no-op: no I/O, and --
//! critically -- **no `FM_TICK` string literal**, so there is nothing to strip
//! and nothing to leak into a `-d`/`-r`/`-e` artifact. The observable-heartbeat
//! variant (`source-bootsmoke/BootSmoke.mc`) is selected ONLY by
//! `monkey.bootsmoke.jungle`, so shipping binaries are clean **by construction**
//! (not by dead-code elimination). The `check_boot_residue.sh` gate is then just
//! belt-and-suspenders. See docs/connectiq-ci-setup.md (#124).
module BootSmoke {
    function tick(n) { }
}
