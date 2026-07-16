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
RUN_TIMEOUT="${CIQ_RUN_TIMEOUT:-180}"   # monkeydo can NEVER outrun this
DNUM="${CIQ_DISPLAY:-99}"
LOG="sim-run.log"

# True iff something is LISTENing on $SIM_PORT (ground truth, as captured by the
# diagnostic). ss is guaranteed present (the job installs iproute2). The filter
# DSL is primary; the column grep is a fallback so readiness never hinges on the
# filter syntax alone. `[:.]${SIM_PORT}[[:space:]]` anchors on the local-address
# column's `:1234 ` (a digit before, e.g. `:41234`, cannot match).
port_listening() {
  ss -ltn "sport = :${SIM_PORT}" 2>/dev/null | grep -q LISTEN \
    || ss -ltn 2>/dev/null | grep -qE "[:.]${SIM_PORT}([[:space:]]|\$)"
}

# Fail-fast if a stale X server or the sim port is already up at entry (e.g. a
# server leaked from a prior step) -- otherwise we would test against the WRONG
# server and a green run would be untrustworthy (#42 re-review round 2, item 2).
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

# `connectiq` is a launcher that forks the real "$SIM_PROC" and returns, so
# liveness is checked by process NAME, not the launcher's PID. Give the launcher
# a startup grace so the pgrep-death check cannot false-fail during its fork
# window (#42 re-review round 2, item 3).
connectiq >/dev/null 2>&1 &
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

set +e
timeout --signal=KILL "${RUN_TIMEOUT}" monkeydo "$PRG" "$DEVICE" -t 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then
  echo "::error::monkeydo timed out after ${RUN_TIMEOUT}s"; exit 1
fi

python3 scripts/check_ciq_tests.py "$LOG"
