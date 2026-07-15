# Self-hosted `connectiq` runner kit — FatigueMeter CI

PR #35's `.github/workflows/ci.yml` runs its SDK-dependent jobs (`compile`,
`simulate`) on a self-hosted runner labelled **`connectiq`** with the Connect IQ
SDK, the `edge1050` device definition, and the Qt simulator pre-baked. Until
such a runner is **registered and online**, those jobs sit queued and the
required **`ci-required`** check never posts green.

This kit stands that runner up. **It runs on infrastructure you (the repo owner)
control** — nothing here provisions a runner for you, and the SDK/device URLs,
the Garmin EULA acceptance, and the GitHub registration token are all
**operator-supplied**. Be clear-eyed about that: this is scaffolding + a
runbook, not a hosted service.

Contents:

| File | Purpose |
|---|---|
| `Dockerfile` | Ubuntu 24.04 image: JDK 17 + openssl/unzip/curl/git + Qt/X libs, SDK at `~/.ciq-sdk`, devices at `~/.Garmin/ConnectIQ/Devices`, Actions runner in `/actions-runner`, non-root `runner` user. |
| `entrypoint.sh` | Registers the runner (`--labels connectiq`, `--unattended`, `--ephemeral`), de-registers on shutdown, then `run.sh`. |
| `docker-compose.yml` | One `runner` service wiring the build args + runtime env; `restart: unless-stopped`. |
| `README.md` | This runbook. |

---

## 1. Prerequisites

- A host you control that can reach **both** `github.com` (runner download +
  registration + job traffic) **and** `developer.garmin.com` (SDK + device
  bundle download at image-build time).
- **Docker** with the Compose plugin (`docker compose version`). ~4 GB free disk
  for the image; the SDK + devices dominate.
- The host CPU arch is `amd64` or `arm64` (the Dockerfile selects the matching
  runner tarball). Garmin only ships an x86-64 Linux SDK, so **build/run on
  `amd64`** for the simulator to work.
- A **bare-VM alternative** (no Docker) is in section 8.

---

## 2. Obtain `CIQ_SDK_URL` and `CIQ_DEVICES_URL` from the SDK Manager

These URLs are **not** hardcoded anywhere in this kit and are **not** derivable
from the version number — Garmin serves them behind the SDK Manager's manifest,
gated by the EULA. You resolve them once and pin them.

1. Download the **Connect IQ SDK Manager** from
   <https://developer.garmin.com/connect-iq/sdk/> (free Garmin developer
   account required) and launch it.
2. In the **SDK** tab, select version **7.4.3** (this is `CIQ_SDK_VERSION`,
   matching `ci.yml`), accept the licence, and install it. The manager fetches a
   file named like `connectiq-sdk-lin-7.4.3-<build>.zip`.
   - Capture the exact download URL — watch the SDK Manager's network activity,
     or copy the on-disk zip to a location your build host can `curl` (e.g. an
     internal artifact store / file server / `file://` served over your LAN).
     That URL/path is **`CIQ_SDK_URL`**.
3. In the **Devices** tab, install **Edge 1050** (and, to make the whole compile
   matrix pass, also `edge1040`, `edge840`, `edge540`, `edgeexplore2`, `fr965`,
   `fr955`, `fenix7x`). Device definitions land in
   `~/.Garmin/ConnectIQ/Devices`.
   - Package the device folder(s) you need into a zip and host it where the
     build host can `curl` it. That URL/path is **`CIQ_DEVICES_URL`**. The zip's
     contents are unpacked directly into `~/.Garmin/ConnectIQ/Devices` in the
     image, so zip the *device folders* (e.g. `edge1050/…`), not a wrapping
     parent directory.

> **EULA.** Building the image with these URLs downloads Garmin software. You
> must pass **`CIQ_EULA_ACCEPT=1`**; doing so means **you accept Garmin's Connect
> IQ SDK licence** on your own behalf. The build refuses to download otherwise.
> Only build this on infrastructure you control.

There are deliberately **no default/fake URLs**: an empty `CIQ_SDK_URL` or
`CIQ_DEVICES_URL` fails the build immediately with a clear message.

---

## 3. Get a `RUNNER_TOKEN` (short-lived registration token)

Either:

- **UI:** repo **Settings → Actions → Runners → New self-hosted runner**. Copy
  the token shown in the `./config.sh --token <TOKEN>` line, **or**
- **CLI:**
  ```sh
  gh api -X POST repos/Macrophage87/FatigueMeter/actions/runners/registration-token \
    --jq .token
  ```

> Registration tokens **expire ~1 hour** after issuance. Generate it right
> before `docker compose up`. It is only needed at registration time; you do not
> store a long-lived secret on the runner.

---

## 4. Build and run

From `ci/self-hosted-runner/`:

```sh
# --- build (downloads the Garmin SDK + devices; accepts the EULA) ---
export CIQ_SDK_URL='https://…/connectiq-sdk-lin-7.4.3-<build>.zip'
export CIQ_DEVICES_URL='https://…/ciq-devices-edge1050.zip'
export CIQ_EULA_ACCEPT=1
# Optional but recommended: pin+verify the runner. Check the latest at
# https://github.com/actions/runner/releases and copy its tarball SHA-256.
export RUNNER_VERSION=2.328.0            # PLACEHOLDER — verify latest
export RUNNER_TARBALL_SHA256='<sha256 from the release page>'
docker compose build

# --- run (registers the runner) ---
export GITHUB_REPO_URL='https://github.com/Macrophage87/FatigueMeter'
export RUNNER_TOKEN='<token from step 3>'
docker compose up -d
docker compose logs -f runner        # watch it register + go "Listening for Jobs"
```

---

## 5. Verify the runner is online

1. Repo **Settings → Actions → Runners** shows a runner (default name
   `connectiq-fatiguemeter`) as **Idle/Online** carrying the labels
   `self-hosted` and **`connectiq`**.
2. Re-run PR #35's checks: on the PR, **Checks → CI → Re-run jobs** (or push an
   empty commit to `claude/add-ci-workflow`). The **`compile`** matrix (8
   devices) should now **execute** on your runner instead of sitting queued, and
   `ci-required` should resolve.
   - `simulate` is `continue-on-error` (advisory) — it may still be flaky; that
     is expected and does **not** block `ci-required`.
   - `manifest-lint` / `traceability` run on GitHub-hosted `ubuntu-latest` and
     were already green.

> **First-run note (cache miss).** `ci.yml` caches `~/.ciq-sdk` +
> `~/.Garmin/ConnectIQ/Devices` and, on a *cache miss*, runs
> `scripts/install_ciq_sdk.sh`. The very first job on a fresh runner is a cache
> miss. The image bakes `CIQ_SDK_URL` / `CIQ_SDK_VERSION` / `CIQ_EULA_ACCEPT`
> into the runner's environment precisely so that fallback re-materialises the
> SDK cleanly instead of failing on an unset URL. Devices are already baked in.
> After the first successful run the Actions cache is warm and the install step
> is skipped.

---

## 6. Compile-break dry-run (prove the required check can go RED)

Do this **before** enabling branch protection — a required check that can never
fail is as dangerous as one that can never pass.

```sh
git checkout -b scratch/ci-break origin/main
# introduce a deliberate monkeyc error, e.g. append a bad token to a source file:
printf '\nclass __CiBreak { function x() { return notAThing; } }\n' >> source/Constants.mc
git commit -am "TEMP: break compile to verify ci-required reddens"
git push origin scratch/ci-break
# open a PR from scratch/ci-break -> main, watch the `compile` job FAIL and
# `ci-required` turn RED.
```

Then revert:

```sh
git push origin --delete scratch/ci-break   # close/delete the scratch PR + branch
```

Confirm on a clean PR that `ci-required` goes **green** again.

---

## 7. ONLY THEN: enable branch protection on `ci-required`

Once (a) the runner is online, (b) a fully-green `ci-required` run has been
**observed**, and (c) the compile-break dry-run reddened it, require the check.
This is a manual repo-admin step (the same one referenced in PR #35 and
`BUILD.md`):

```sh
gh api -X PUT repos/Macrophage87/FatigueMeter/branches/main/protection \
  -H "Accept: application/vnd.github+json" \
  -f 'required_status_checks[strict]=true' \
  -f 'required_status_checks[checks][][context]=ci-required' \
  -f 'enforce_admins=true' \
  -f 'required_pull_request_reviews[required_approving_review_count]=1' \
  -f 'restrictions=' \
  -F 'restrictions=null'
```

(Adjust review/admin settings to your policy; the load-bearing parts are
`required_status_checks.strict=true` and the `ci-required` context.) **Do not
enable this earlier** — per the blunt note in `ci.yml`/`BUILD.md`, requiring
`ci-required` before a `connectiq` runner is online blocks every merge on a
check that cannot post.

---

## 8. Bare-VM (non-Docker) alternative

If you would rather run the runner directly on a Linux VM (still amd64, still
reaching github.com + developer.garmin.com), the steps are the same, minus the
container. Sketch:

```sh
#!/usr/bin/env bash
set -euo pipefail

# --- 8.1 system deps (Ubuntu 24.04): JDK + tools + Qt/X libs (mirrors ci.yml) --
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  openjdk-17-jdk-headless openssl unzip curl git \
  xvfb libxkbcommon-x11-0 libxcb-xinerama0 libxcb-icccm4 libxcb-image0 \
  libxcb-keysyms1 libxcb-render-util0 libgl1 libnss3 libasound2t64 libicu74

# --- 8.2 Connect IQ SDK via the SDK Manager, exposed at ~/.ciq-sdk/bin ---------
# Install SDK 7.4.3 with the SDK Manager (GUI) or its CLI, accepting the EULA,
# then make it resolve where ci.yml expects it:
#   mkdir -p ~/.ciq-sdk && unzip connectiq-sdk-lin-7.4.3-<build>.zip -d ~/.ciq-sdk
#   chmod +x ~/.ciq-sdk/bin/*
# ci.yml adds ~/.ciq-sdk/bin to PATH per-job; for interactive use also:
#   echo 'export PATH="$HOME/.ciq-sdk/bin:$PATH"' >> ~/.bashrc

# --- 8.3 device definitions in ~/.Garmin/ConnectIQ/Devices --------------------
# Install edge1050 (+ the other manifest devices) via the SDK Manager's Devices
# tab; they land in ~/.Garmin/ConnectIQ/Devices automatically.

# --- 8.4 the Actions runner ---------------------------------------------------
RUNNER_VERSION=2.328.0     # PLACEHOLDER — verify https://github.com/actions/runner/releases
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -fsSL -o runner.tar.gz \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
# (verify the SHA-256 from the release page before extracting)
tar xzf runner.tar.gz
./bin/installdependencies.sh

# --- 8.5 register with the connectiq label (NOT as root) ----------------------
./config.sh \
  --url https://github.com/Macrophage87/FatigueMeter \
  --token "<RUNNER_TOKEN>" \
  --name connectiq-vm \
  --labels connectiq \
  --unattended

# --- 8.6 install as a systemd service so it survives reboots ------------------
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
# To remove later: sudo ./svc.sh stop && sudo ./svc.sh uninstall && ./config.sh remove --token <NEW_TOKEN>
```

The bare-VM runner is long-lived (not ephemeral). Then follow sections 5–7
unchanged: verify online → compile-break dry-run → enable branch protection.

---

## Maintenance notes

- **Runner version drift.** `RUNNER_VERSION` is a **placeholder** — GitHub
  deprecates old runners and will eventually refuse their registration. Check
  <https://github.com/actions/runner/releases> periodically, bump the arg,
  supply the matching `RUNNER_TARBALL_SHA256`, and rebuild
  (`docker compose build --pull && docker compose up -d --force-recreate`).
- **SDK version bump.** If `ci.yml`'s `CIQ_SDK_VERSION` changes, resolve the new
  `CIQ_SDK_URL`/`CIQ_DEVICES_URL`, update `CIQ_SDK_VERSION`, and rebuild.
- **Token expiry.** Registration tokens are short-lived; re-issue (section 3)
  each time you (re-)register a runner.
- **`ci-required` stays pending** until this runner is online. That is by
  design, not a bug.
