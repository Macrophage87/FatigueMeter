#!/usr/bin/env bash
# Launch the CIQ simulator headlessly, wait for it to actually accept IPC,
# run the test PRG, then hand the captured output to the strict parser.
set -euo pipefail

PRG="${1:?usage: run_ciq_tests.sh <test.prg> <device>}"
DEVICE="${2:?usage: run_ciq_tests.sh <test.prg> <device>}"
SIM_PORT="${CIQ_SIM_PORT:-1234}"   # sim's monkeydo/shell IPC port; verify per SDK
LOG="sim-run.log"

export DISPLAY=":99"
Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &
XVFB_PID=$!
connectiq >/dev/null 2>&1 &
SIM_PID=$!
cleanup() { kill "$SIM_PID" "$XVFB_PID" 2>/dev/null || true; }
trap cleanup EXIT

ready=0
for _ in $(seq 1 60); do            # up to ~120s, bounded
  if (exec 3<>"/dev/tcp/127.0.0.1/${SIM_PORT}") 2>/dev/null; then
    exec 3>&- 3<&-; ready=1; break
  fi
  if ! kill -0 "$SIM_PID" 2>/dev/null; then
    echo "::error::simulator exited before becoming ready"; exit 1
  fi
  sleep 2
done
[ "$ready" = 1 ] || { echo "::error::simulator not ready on :${SIM_PORT}"; exit 1; }

set +e
monkeydo "$PRG" "$DEVICE" -t 2>&1 | tee "$LOG"
set -e

python3 scripts/check_ciq_tests.py "$LOG"
