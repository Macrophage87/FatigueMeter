#!/usr/bin/env bash
# Launch the Connect IQ simulator headlessly, wait until it actually opens its
# IPC port, run the compiled --unit-test PRG under a HARD timeout, then hand the
# captured output to the strict fail-closed parser. The readiness probe (not a
# `sleep`) and the `timeout` are what make this fail-fast instead of hanging to
# the job limit the way the image's own tester.sh does (issue #42).
#
# Port/proc are PINNED from PR #43's DIAGNOSTIC run (run 29509335863): the sim
# process is `/connectiq/bin/simulator` and it LISTENs on 0.0.0.0:1234.
#
# Readiness is probed with `ss` (from iproute2, installed by the job), NOT bash's
# /dev/tcp: the first PR-#43 run proved this container's bash /dev/tcp redirection
# never connects even though `ss` shows the sim listening on :1234, so a /dev/tcp
# probe times out forever ("simulator not ready") while the sim is in fact up.
set -euo pipefail

PRG="${1:?usage: run_ciq_tests.sh <test.prg> <device>}"
DEVICE="${2:?usage: run_ciq_tests.sh <test.prg> <device>}"
SIM_PORT="${CIQ_SIM_PORT:-1234}"        # PINNED from `ss -ltnp` (DIAGNOSTIC run)
SIM_PROC="${CIQ_SIM_PROC:-simulator}"   # PINNED real-sim process name (DIAGNOSTIC)
RUN_TIMEOUT="${CIQ_RUN_TIMEOUT:-90}"    # monkeydo can NEVER outrun this
DNUM="${CIQ_DISPLAY:-99}"
LOG="sim-run.log"

# The SIMULATOR loads device definitions from $HOME/.Garmin/ConnectIQ/Devices.
# In a GitHub Actions container HOME=/github/home, but the image downloaded the
# sim device defs under a DIFFERENT home at build time -- so the sim logged
# "Failed to load .../Devices/edge1050/compiler.json" and monkeydo then hung
# forever waiting for an app that could not start (PR #43 run 28; monkeyc
# compiles fine because it reads the SDK's own device defs, not these). Point
# HOME at wherever the sim device defs actually live so the sim can load
# "$DEVICE". Search the likely homes first, then fall back to a full scan.
if [ ! -e "$HOME/.Garmin/ConnectIQ/Devices/${DEVICE}/compiler.json" ]; then
  # `-print -quit` stops find at the first match WITHOUT a `| head` pipe -- a
  # `find | head` pipeline SIGPIPEs find, and under `set -o pipefail`/`set -e`
  # that aborts the whole script with exit 141 (PR #43 run 30). Wrap in set +e
  # so a missing search root's non-zero exit can't trip errexit either.
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

# True iff something is LISTENing on $SIM_PORT (ground truth, as captured by the
# diagnostic). ss is guaranteed present (the job installs iproute2). The filter
# DSL is primary; the column grep is a fallback so readiness never hinges on the
# filter syntax alone. `[:.]${SIM_PORT}[[:space:]]` anchors on the local-address
# column's `:1234 ` (a digit before, e.g. `:41234`, cannot match).
port_listening() {
  ss -ltn "sport = :${SIM_PORT}" 2>/dev/null | grep -q LISTEN \
    || ss -ltn 2>/dev/null | grep -qE "[:.]${SIM_PORT}([[:space:]]|\$)"
}

# Belt-and-suspenders: reap any pre-existing simulator that leaked from an
# earlier step in this job before we assert a clean slate. A leaked sim may be
# display-less and NOT listening on the port (so the port guard below misses it)
# yet still keeps `pgrep -f simulator` alive, which would wedge the readiness
# loop (#42 re-review round 2, item 2; the diagnostic-leak actually observed on
# PR #43 run 25). This script owns the sim lifecycle in the `simulate` job.
if pgrep -f "$SIM_PROC" >/dev/null 2>&1; then
  echo "note: reaping pre-existing '$SIM_PROC' process(es) before start"
  pkill -f "$SIM_PROC" 2>/dev/null || true
  sleep 2
fi

# Fail-fast if a stale X server or the sim port is STILL up at entry -- otherwise
# we would test against the WRONG server and a green run would be untrustworthy.
if [ -e "/tmp/.X11-unix/X${DNUM}" ]; then
  echo "::error::display :${DNUM} already in use at entry"; exit 1
fi
if port_listening; then
  echo "::error::sim port ${SIM_PORT} already occupied at entry"; exit 1
fi

export DISPLAY=":${DNUM}"
Xvfb ":${DNUM}" -screen 0 1280x1024x24 >/dev/null 2>&1 &
XVFB_PID=$!
cleanup() { pkill -f "$SIM_PROC" 2>/dev/null || true; kill "$XVFB_PID" 2>/dev/null || true; }
trap cleanup EXIT

# Wait for Xvfb to actually accept connections BEFORE launching the Qt sim.
xready=0
for _ in $(seq 1 30); do
  if xdpyinfo -display ":${DNUM}" >/dev/null 2>&1; then xready=1; break; fi
  kill -0 "$XVFB_PID" 2>/dev/null || { echo "::error::Xvfb failed to start"; exit 1; }
  sleep 1
done
[ "$xready" = 1 ] || { echo "::error::Xvfb not ready on :${DNUM}"; exit 1; }

# Launch the simulator EXACTLY as the image's own tester.sh does -- `simulator`
# directly (not the `connectiq` wrapper). tester.sh is the reference that runs
# monkeydo successfully; when we launched via `connectiq` instead, the sim came
# up and monkeydo connected but then hung to the timeout (PR #43 run 26), so we
# mirror the proven invocation. Liveness is still checked by process NAME. Give a
# startup grace so the pgrep-death check cannot false-fail during launch.
simulator >sim-sim.log 2>&1 &
sleep 5

ready=0
for _ in $(seq 1 60); do                # up to ~120s, bounded
  if port_listening; then ready=1; break; fi
  pgrep -f "$SIM_PROC" >/dev/null 2>&1 || { echo "::error::simulator process gone before ready"; exit 1; }
  sleep 2
done
if [ "$ready" != 1 ]; then
  # Dump ground-truth state so a repeat failure is self-explaining, not opaque.
  echo "::error::simulator not ready on :${SIM_PORT}"
  echo "== ss -ltnp =="; ss -ltnp 2>/dev/null || true
  echo "== pgrep -af 'onnect|imulator' =="; pgrep -af 'onnect|imulator' || true
  exit 1
fi

# Run the test suite. stdbuf -oL/-eL keeps output line-buffered so partial
# results survive the KILL if monkeydo is still buffering when the timeout fires.
set +e
stdbuf -oL -eL timeout --signal=KILL "${RUN_TIMEOUT}" monkeydo "$PRG" "$DEVICE" -t >"$LOG" 2>&1
rc=$?
set -e

# ALWAYS echo the captured output so its exact format is readable via the Actions
# API even when the artifact blob download is blocked; it is also what the parser
# patterns get pinned from.
echo "===== BEGIN sim-run.log (monkeydo output) ====="
cat "$LOG" || true
echo "===== END sim-run.log ====="
# The simulator's own stdout/stderr often carries the 'Run No Evil' results (and
# any app load/crash diagnostics) when monkeydo itself prints nothing.
echo "===== BEGIN simulator output (sim-sim.log, last 80 lines) ====="
tail -80 sim-sim.log 2>/dev/null || true
echo "===== END simulator output ====="

if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then
  echo "::error::monkeydo timed out after ${RUN_TIMEOUT}s"; exit 1
fi

python3 scripts/check_ciq_tests.py "$LOG"
