# =============================================================================
# FatigueMeter — self-hosted GitHub Actions runner, pre-baked for `connectiq`
# -----------------------------------------------------------------------------
# This image builds the `[self-hosted, connectiq]` runner that PR #35's
# `.github/workflows/ci.yml` requires. The `compile` and `simulate` jobs expect,
# on the runner host:
#   * a JVM (JDK 17)                         — the Connect IQ toolchain is Java
#   * the Connect IQ SDK on PATH at          $HOME/.ciq-sdk/bin
#   * the edge1050 (and sibling) device defs at $HOME/.Garmin/ConnectIQ/Devices
#   * Qt/X runtime libs + xvfb               — the headless simulator (sim job)
#   * openssl                                — the per-run throwaway developer key
# This Dockerfile bakes all of that so those jobs run without any per-run
# Garmin download.
#
# HONESTY / SCOPE:
#   * This image does NOT provision or register a runner by itself. Registration
#     happens at container start (see entrypoint.sh) using an operator-supplied,
#     short-lived RUNNER_TOKEN.
#   * The SDK zip URL (CIQ_SDK_URL) and the device-bundle URL (CIQ_DEVICES_URL)
#     are NOT hardcoded and are NOT knowable from the version number alone.
#     Garmin serves them behind the Connect IQ SDK Manager, gated by the SDK
#     manifest and the Garmin EULA. The OPERATOR resolves these URLs from the
#     SDK Manager (see README.md) and passes them as build args. There are no
#     fake/placeholder URLs in this file — an empty CIQ_SDK_URL / CIQ_DEVICES_URL
#     fails the build on purpose.
#   * Building with CIQ_SDK_URL/CIQ_DEVICES_URL set downloads Garmin software.
#     You must set CIQ_EULA_ACCEPT=1 to proceed; doing so means YOU, the
#     operator, accept Garmin's Connect IQ SDK licence on your own behalf. Only
#     ever build this on infrastructure you control.
# =============================================================================
FROM ubuntu:24.04

# ----------------------------- build arguments -------------------------------
# Pinned SDK version. Kept in lockstep with ci.yml's `CIQ_SDK_VERSION`.
ARG CIQ_SDK_VERSION=7.4.3

# REQUIRED, operator-supplied. No defaults — an unset value errors out below.
#   CIQ_SDK_URL     : exact Linux SDK zip (connectiq-sdk-lin-<ver>-<build>.zip),
#                     resolved from the Connect IQ SDK Manager.
#   CIQ_DEVICES_URL : the device bundle/zip that provides the edge1050 (and the
#                     other manifest devices) definitions. Ships SEPARATELY from
#                     the SDK zip — see ci.yml's cache of ~/.Garmin/.../Devices.
ARG CIQ_SDK_URL
ARG CIQ_DEVICES_URL

# EULA gate. Must be exactly "1"; anything else fails the build before download.
ARG CIQ_EULA_ACCEPT

# GitHub Actions runner version.
# !! PLACEHOLDER — VERIFY BEFORE USE !!
# Check the latest release at https://github.com/actions/runner/releases and set
# --build-arg RUNNER_VERSION=<latest> (without the leading "v"). Keep this
# current: GitHub deprecates old runner versions and will refuse registration
# from a runner that is too old. The tarball's published SHA-256 is on that
# release page; supply it via RUNNER_TARBALL_SHA256 to enable integrity
# checking (left empty = skip the checksum, with a warning).
ARG RUNNER_VERSION=2.328.0
ARG RUNNER_TARBALL_SHA256=

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_HOME=/actions-runner \
    CIQ_SDK_VERSION=${CIQ_SDK_VERSION}

# ----------------------------- system packages -------------------------------
# JDK 17 (distro openjdk-17), the build/runtime tools the scripts call
# (openssl, unzip, curl, git), and the Qt/X runtime libs the headless simulator
# needs. The libxcb-* / libgl1 / libnss3 / libasound2t64 / xvfb set mirrors the
# `apt-get install` line in ci.yml's `simulate` job exactly.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl unzip git openssl sudo tini \
        openjdk-17-jdk-headless \
        xvfb \
        libxkbcommon-x11-0 \
        libxcb-xinerama0 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-render-util0 \
        libgl1 \
        libnss3 \
        libasound2t64 \
        libicu74 \
    ; \
    rm -rf /var/lib/apt/lists/*

# ----------------------------- non-root runner user --------------------------
# The GitHub Actions runner refuses to `config.sh` as root (RUNNER_ALLOW_
# RUNASROOT override exists but is discouraged). Create an unprivileged `runner`
# user. It gets passwordless sudo ONLY for apt-get, because ci.yml's simulate
# job runs `sudo apt-get install` for the Qt deps (already present in this
# image, so that step is a fast no-op, but the sudo call must still succeed).
RUN set -eux; \
    useradd --create-home --shell /bin/bash runner; \
    echo 'runner ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt' \
        > /etc/sudoers.d/runner-apt; \
    chmod 0440 /etc/sudoers.d/runner-apt

# ----------------------------- Connect IQ SDK --------------------------------
# EULA + required-URL gates FIRST, so the build fails clearly and BEFORE any
# download when the operator has not supplied the inputs.
RUN set -eux; \
    if [ "${CIQ_EULA_ACCEPT}" != "1" ]; then \
        echo "ERROR: refusing to download the Garmin Connect IQ SDK without EULA acceptance."; \
        echo "       Re-run with --build-arg CIQ_EULA_ACCEPT=1 to accept Garmin's SDK licence."; \
        exit 1; \
    fi; \
    if [ -z "${CIQ_SDK_URL}" ]; then \
        echo "ERROR: CIQ_SDK_URL is empty. Resolve the exact Linux SDK zip URL for"; \
        echo "       version ${CIQ_SDK_VERSION} from the Connect IQ SDK Manager and pass it"; \
        echo "       with --build-arg CIQ_SDK_URL=... (see ci/self-hosted-runner/README.md)."; \
        exit 1; \
    fi; \
    if [ -z "${CIQ_DEVICES_URL}" ]; then \
        echo "ERROR: CIQ_DEVICES_URL is empty. The edge1050 device definition ships"; \
        echo "       separately from the SDK zip. Resolve its URL from the SDK Manager"; \
        echo "       (Devices tab) and pass --build-arg CIQ_DEVICES_URL=... ."; \
        exit 1; \
    fi

# Install the SDK to /opt/ciq-sdk and expose it at $HOME/.ciq-sdk (the path
# ci.yml puts on PATH: `echo "$HOME/.ciq-sdk/bin" >> "$GITHUB_PATH"`). A symlink
# from the runner's home keeps a single on-disk copy.
RUN set -eux; \
    mkdir -p /opt/ciq-sdk; \
    curl -fsSL "${CIQ_SDK_URL}" -o /tmp/ciq-sdk.zip; \
    unzip -q /tmp/ciq-sdk.zip -d /opt/ciq-sdk; \
    rm -f /tmp/ciq-sdk.zip; \
    # Some SDK zips wrap everything in a single top-level dir; flatten so that
    # /opt/ciq-sdk/bin exists regardless.
    if [ ! -d /opt/ciq-sdk/bin ]; then \
        inner="$(find /opt/ciq-sdk -maxdepth 2 -type d -name bin | head -1)"; \
        if [ -n "${inner}" ]; then \
            base="$(dirname "${inner}")"; \
            cp -a "${base}/." /opt/ciq-sdk/; \
        fi; \
    fi; \
    chmod +x /opt/ciq-sdk/bin/* 2>/dev/null || true; \
    ln -s /opt/ciq-sdk /home/runner/.ciq-sdk

# ----------------------------- device definitions ----------------------------
# Devices live in $HOME/.Garmin/ConnectIQ/Devices (see ci.yml's cache path).
# Unzip the operator-supplied device bundle there. The bundle should contain at
# least edge1050; ideally every device in manifest.xml so the whole compile
# matrix passes (edge1050, edge1040, edge840, edge540, edgeexplore2, fr965,
# fr955, fenix7x).
RUN set -eux; \
    mkdir -p /home/runner/.Garmin/ConnectIQ/Devices; \
    curl -fsSL "${CIQ_DEVICES_URL}" -o /tmp/ciq-devices.zip; \
    unzip -q /tmp/ciq-devices.zip -d /home/runner/.Garmin/ConnectIQ/Devices; \
    rm -f /tmp/ciq-devices.zip

# ----------------------------- Actions runner --------------------------------
RUN set -eux; \
    mkdir -p "${RUNNER_HOME}"; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in \
        amd64) rarch=x64 ;; \
        arm64) rarch=arm64 ;; \
        *) echo "unsupported arch: ${arch}"; exit 1 ;; \
    esac; \
    tarball="actions-runner-linux-${rarch}-${RUNNER_VERSION}.tar.gz"; \
    curl -fsSL -o "/tmp/${tarball}" \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${tarball}"; \
    if [ -n "${RUNNER_TARBALL_SHA256}" ]; then \
        echo "${RUNNER_TARBALL_SHA256}  /tmp/${tarball}" | sha256sum -c -; \
    else \
        echo "WARNING: RUNNER_TARBALL_SHA256 not provided; skipping runner tarball checksum."; \
    fi; \
    tar -xzf "/tmp/${tarball}" -C "${RUNNER_HOME}"; \
    rm -f "/tmp/${tarball}"; \
    "${RUNNER_HOME}/bin/installdependencies.sh"

# ----------------------------- ownership + fallback env ----------------------
# Persist the SDK inputs as runtime env for the `runner` user. Rationale: ci.yml
# caches ~/.ciq-sdk + ~/.Garmin/.../Devices and, on a CACHE MISS, runs
# ./scripts/install_ciq_sdk.sh (which requires CIQ_SDK_URL, CIQ_SDK_VERSION and
# CIQ_EULA_ACCEPT). On a fresh pre-baked runner the first job sees a cache miss,
# so exposing these lets that fallback re-materialise the SDK cleanly instead of
# hard-failing on an unset URL. The device defs are already baked in, so the
# script's device step stays a no-op.
ENV CIQ_SDK_URL=${CIQ_SDK_URL} \
    CIQ_DEVICES_URL=${CIQ_DEVICES_URL} \
    CIQ_EULA_ACCEPT=1
RUN chown -R runner:runner /opt/ciq-sdk "${RUNNER_HOME}" /home/runner

COPY --chown=runner:runner entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER runner
WORKDIR ${RUNNER_HOME}

# tini reaps the run.sh/worker process tree so SIGTERM from `docker stop`
# reaches entrypoint.sh's trap (which de-registers the runner).
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
