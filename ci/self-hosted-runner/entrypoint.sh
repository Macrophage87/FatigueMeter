#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh — register + run the `connectiq` self-hosted Actions runner.
# -----------------------------------------------------------------------------
# On container start this:
#   1. validates the operator-supplied env,
#   2. registers this runner against the repo with the `connectiq` label,
#   3. traps SIGTERM/SIGINT so a `docker stop` de-registers the runner, and
#   4. exec's ./run.sh to start listening for jobs.
#
# Required env (see docker-compose.yml / README.md):
#   GITHUB_REPO_URL  e.g. https://github.com/Macrophage87/FatigueMeter
#   RUNNER_TOKEN     the SHORT-LIVED registration token from
#                    Settings -> Actions -> Runners -> New self-hosted runner
#                    (or: gh api -X POST \
#                       repos/Macrophage87/FatigueMeter/actions/runners/registration-token)
# Optional env:
#   RUNNER_NAME      display name in the Runners list (default: connectiq-<host>)
#   RUNNER_LABELS    extra labels appended to the required `connectiq` label
#   RUNNER_EPHEMERAL "1" (default) => --ephemeral: the runner de-registers after
#                    ONE job. Recommended: it keeps the workspace clean and pairs
#                    with `restart: unless-stopped` for a fresh runner per job.
#                    Set to "0" for a long-lived runner.
# =============================================================================
set -euo pipefail

RUNNER_HOME="${RUNNER_HOME:-/actions-runner}"
cd "${RUNNER_HOME}"

# ----------------------------- fail-fast validation --------------------------
if [ -z "${GITHUB_REPO_URL:-}" ]; then
    echo "FATAL: GITHUB_REPO_URL is unset." >&2
    echo "       Set it to the repo, e.g. https://github.com/Macrophage87/FatigueMeter" >&2
    exit 1
fi
if [ -z "${RUNNER_TOKEN:-}" ]; then
    echo "FATAL: RUNNER_TOKEN is unset." >&2
    echo "       Get a short-lived registration token from the repo:" >&2
    echo "       Settings -> Actions -> Runners -> New self-hosted runner, or" >&2
    echo "       gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token" >&2
    echo "       (registration tokens expire ~1h after issuance)." >&2
    exit 1
fi

RUNNER_NAME="${RUNNER_NAME:-connectiq-$(hostname)}"
RUNNER_EPHEMERAL="${RUNNER_EPHEMERAL:-1}"

# The `connectiq` label is REQUIRED — ci.yml targets `[self-hosted, connectiq]`.
# Any operator-supplied RUNNER_LABELS are appended, never replacing `connectiq`.
LABELS="connectiq"
if [ -n "${RUNNER_LABELS:-}" ]; then
    LABELS="${LABELS},${RUNNER_LABELS}"
fi

# ----------------------------- de-registration trap --------------------------
# On SIGTERM/SIGINT (docker stop / compose down), remove the runner from the
# repo so it doesn't linger as an offline entry. Best-effort: never block
# shutdown on it.
deregister() {
    echo "Caught shutdown signal; removing runner registration..."
    ./config.sh remove --token "${RUNNER_TOKEN}" || \
        echo "WARN: config.sh remove failed (token may have expired); remove it in the UI." >&2
}
trap 'deregister; exit 0' SIGTERM SIGINT

# ----------------------------- configure -------------------------------------
CONFIG_ARGS=(
    --url "${GITHUB_REPO_URL}"
    --token "${RUNNER_TOKEN}"
    --name "${RUNNER_NAME}"
    --labels "${LABELS}"
    --unattended
    --replace
)
if [ "${RUNNER_EPHEMERAL}" = "1" ]; then
    CONFIG_ARGS+=(--ephemeral)
fi

echo "Registering runner '${RUNNER_NAME}' with labels '${LABELS}' against ${GITHUB_REPO_URL}"
./config.sh "${CONFIG_ARGS[@]}"

# ----------------------------- run -------------------------------------------
# exec so run.sh becomes PID 1's child under tini and receives our signals.
# `& wait` keeps the trap responsive while run.sh runs in the foreground group.
./run.sh &
RUN_PID=$!
wait "${RUN_PID}"
