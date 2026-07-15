#!/usr/bin/env bash
# FRAGILE: Garmin serves versioned SDK zips (connectiq-sdk-lin-<ver>-<build>.zip)
# behind the SDK-Manager manifest, and DEVICE definitions download separately
# into ~/.Garmin/ConnectIQ/Devices. Neither URL is predictable from <ver> alone,
# which is why a pre-baked self-hosted runner is the PRIMARY path (this script
# is the hosted-runner fallback). Resolve the exact URLs ONCE and pin them.
set -euo pipefail

# --- Required-input gates FIRST, before any download/extract -----------------
# Fail closed on missing config BEFORE touching the network or disk, so we never
# fetch/extract the SDK and only THEN refuse on licence (previous ordering bug).
VER="${CIQ_SDK_VERSION:?set CIQ_SDK_VERSION}"
SDK_URL="${CIQ_SDK_URL:?resolve+pin the exact Linux SDK zip URL for ${VER}}"
# Non-interactive EULA acceptance accepts Garmin's SDK licence on the repo
# owner's behalf — only ever run on infrastructure the owner controls. Checked
# up front so we refuse on licence BEFORE downloading anything.
: "${CIQ_EULA_ACCEPT:?refusing to auto-accept Garmin EULA unless CIQ_EULA_ACCEPT=1}"

DEST="$HOME/.ciq-sdk"
mkdir -p "$DEST" "$HOME/.Garmin/ConnectIQ/Devices"
curl -fsSL "$SDK_URL" -o /tmp/ciq-sdk.zip
unzip -q /tmp/ciq-sdk.zip -d "$DEST"
chmod +x "$DEST"/bin/* 2>/dev/null || true

# If monkeyc later reports 'edge1050 is unknown', the device bundle is missing.
# On the pre-baked/self-hosted runner it is already in ~/.Garmin/ConnectIQ/Devices;
# on a hosted runner, fetch the pinned device bundle for ${VER} here.
