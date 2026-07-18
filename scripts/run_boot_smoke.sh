#!/usr/bin/env bash
# #124 boot-smoke runner — boot the REAL compiled DataField headlessly with
# `monkeydo` (NO `-t`) so the sim free-runs compute() at ~1 Hz, then hand the
# captured tick stream + any CIQ_LOG.YML crash log to the fail-closed parser.
#
# STANDALONE by design (panel Minor 2): this DUPLICATES run_ciq_tests.sh's sim
# lifecycle (HOME/device-def resolution, Xvfb, ss readiness probe, timeout)
# rather than refactoring that battle-scarred, ci-required script. Drift risk is
# accepted: a future fix to the lifecycle in run_ciq_tests.sh will NOT propagate
# here and must be mirrored. See docs/connectiq-ci-setup.md.
#
# KEY DIFFERENCE vs run_ciq_tests.sh: a no-`-t` boot FREE-RUNS FOREVER, so
# `timeout --signal=KILL` SIGKILLing it (rc 124 from timeout, or 137 = 128+KILL)
# is the EXPECTED HEALTHY steady state -- NOT a failure. A clean early exit
# (rc 0 before the timeout) is the ANOMALY (a DataField boot should not
# self-terminate). The verdict is delegated to check_boot_smoke.py.
set -euo pipefail

PRG="${1:?usage: run_boot_smoke.sh <boot.prg> <device>}"
DEVICE="${2:?usage: run_boot_smoke.sh <boot.prg> <device>}"
SIM_PORT="${CIQ_SIM_PORT:-1234}"
SIM_PROC="${CIQ_SIM_PROC:-simulator}"
RUN_TIMEOUT="${CIQ_BOOT_TIMEOUT:-30}"   # free-run window; ~1 tick/s -> ~RUN_TIMEOUT ticks when healthy
DNUM="${CIQ_DISPLAY:-99}"
LOG="boot-smoke.log"
CIQLOG_OUT="boot-smoke-ciqlog.yml"

# --- Sim device-def HOME resolution (duplicated from run_ciq_tests.sh:25-50) ---
if [ ! -e "$HOME/.Garmin/ConnectIQ/Devices/${DEVICE}/compiler.json" ]; then
  set +e
  cj="$(find /root /home /github /connectiq -maxdepth 8 -name compiler.json \
          -path '*/.Garmin/ConnectIQ/Devices/*' -print -quit 2>/dev/null)"
  [ -n "$cj" ] || cj="$(find / -maxdepth 9 -name compiler.json \
          -path '*/.Garmin/ConnectIQ/Devices/*' -print -quit 2>/dev/null)"
  set -e
  if [ -n "$cj" ]; then
    export HOME="${cj%/.Garmin/ConnectIQ/Devices/*}"
    echo "note: sim HOME set to $HOME (device defs found)"
  else
    echo "::warning::no ConnectIQ sim device defs found on the image; the run will fail"
  fi
fi

port_listening() {
  ss -ltn "sport = :${SIM_PORT}" 2>/dev/null | grep -q LISTEN \
    || ss -ltn 2>/dev/null | grep -qE "[:.]${SIM_PORT}([[:space:]]|\$)"
}

if pgrep -f "$SIM_PROC" >/dev/null 2>&1; then
  echo "note: reaping pre-existing '$SIM_PROC' process(es) before start"
  pkill -f "$SIM_PROC" 2>/dev/null || true
  sleep 2
fi
if [ -e "/tmp/.X11-unix/X${DNUM}" ]; then echo "::error::display :${DNUM} already in use at entry"; exit 1; fi
if port_listening; then echo "::error::sim port ${SIM_PORT} already occupied at entry"; exit 1; fi

export DISPLAY=":${DNUM}"
Xvfb ":${DNUM}" -screen 0 1280x1024x24 >/dev/null 2>&1 &
XVFB_PID=$!
cleanup() { pkill -f "$SIM_PROC" 2>/dev/null || true; kill "$XVFB_PID" 2>/dev/null || true; }
trap cleanup EXIT

xready=0
for _ in $(seq 1 30); do
  if xdpyinfo -display ":${DNUM}" >/dev/null 2>&1; then xready=1; break; fi
  kill -0 "$XVFB_PID" 2>/dev/null || { echo "::error::Xvfb failed to start"; exit 1; }
  sleep 1
done
[ "$xready" = 1 ] || { echo "::error::Xvfb not ready on :${DNUM}"; exit 1; }

simulator >sim-sim.log 2>&1 &
sleep 5
ready=0
for _ in $(seq 1 60); do
  if port_listening; then ready=1; break; fi
  pgrep -f "$SIM_PROC" >/dev/null 2>&1 || { echo "::error::simulator process gone before ready"; exit 1; }
  sleep 2
done
if [ "$ready" != 1 ]; then
  echo "::error::simulator not ready on :${SIM_PORT}"
  echo "== ss -ltnp =="; ss -ltnp 2>/dev/null || true
  exit 1
fi

# --- BOOT (no `-t`): free-run the DataField; timeout SIGKILLs the healthy run ---
set +e
stdbuf -oL -eL timeout --signal=KILL "${RUN_TIMEOUT}" monkeydo "$PRG" "$DEVICE" >"$LOG" 2>&1
rc=$?
set -e
echo "$rc" > boot-smoke.rc

echo "===== BEGIN boot-smoke.log (monkeydo stdout, first/last 40) ====="
head -40 "$LOG" 2>/dev/null || true; echo "..."; tail -40 "$LOG" 2>/dev/null || true
echo "===== END boot-smoke.log (rc=$rc) ====="
echo "===== BEGIN simulator output (sim-sim.log, last 60) ====="
tail -60 sim-sim.log 2>/dev/null || true
echo "===== END simulator output ====="

# --- AC-1 diagnostic evidence (the go/no-go data a human reads) ---
echo "===== AC-1 DIAGNOSTIC ====="
echo "HOME=$HOME"
echo "FM_TICK count on stdout: $(grep -c 'FM_TICK' "$LOG" 2>/dev/null || echo 0)"
echo "exit rc: $rc  (124/137 = timeout-killed = healthy free-run; 0 = suspect clean early exit)"
echo "-- find CIQ_LOG.YML under \$HOME --"
found_ciqlog="$(find "$HOME" -name 'CIQ_LOG.YML' -print 2>/dev/null | head -5)"
echo "${found_ciqlog:-<none found>}"
if [ -n "$found_ciqlog" ]; then
  cp "$(echo "$found_ciqlog" | head -1)" "$CIQLOG_OUT" 2>/dev/null || true
  echo "-- CIQ_LOG.YML (copied to $CIQLOG_OUT, last 40) --"; tail -40 "$CIQLOG_OUT" 2>/dev/null || true
else
  : > "$CIQLOG_OUT"   # empty file so the parser can scan both channels uniformly
fi
echo "===== END AC-1 DIAGNOSTIC ====="

# Delegate the verdict (fail-closed) to the parser. This job is advisory, so the
# gate exit code is surfaced but does not (yet) block; promotion to ci-required
# follows the AC-5 >=10-run RED/GREEN bar (docs/connectiq-ci-setup.md).
set +e
python3 scripts/check_boot_smoke.py "$LOG" --rc "$rc" --ciqlog "$CIQLOG_OUT" --timeout "$RUN_TIMEOUT"
gate=$?
set -e
if [ "$gate" = 0 ]; then
  echo "BOOT-SMOKE: PASS"
  echo "### Boot-smoke: ✅ PASS (${DEVICE})" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
else
  echo "BOOT-SMOKE: FAIL"
  echo "### Boot-smoke: ❌ FAIL (${DEVICE}) — see the boot-smoke step log" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
fi
exit "$gate"
