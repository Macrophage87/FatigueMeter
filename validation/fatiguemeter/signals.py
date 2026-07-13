"""Synthetic signal generators + real-file ingestion (FIT/CSV).

Synthetic rides produce per-second power/HR/cadence arrays plus a per-second list
of RR intervals (ms), matching what the RideEngine consumes. RR is generated with
a controllable short-term correlation so DFA-α1 responds the way the literature
establishes (higher intensity -> lower α1), plus optional artifact injection and
a respiration component for the "respiration must not manufacture fatigue" check.

These generators are stimuli for a MODEL-CONSISTENCY harness — they encode the
project's stated directions (with wide tolerance), not physiological ground truth.
"""
from __future__ import annotations

import csv
import math
from dataclasses import dataclass
from typing import List, Optional

import numpy as np


@dataclass
class Ride:
    power: List[Optional[float]]
    hr: List[Optional[float]]
    cadence: List[Optional[float]]
    rr_by_second: List[List[float]]
    label: str = ""


def _rr_stream(hr_series, phi, artifact_frac, resp_hz, rng, resp_amp_ms=0.0,
               phi_end=None):
    """Generate a beat-to-beat RR stream (ms) covering the ride, bucketed into the
    second each beat completes. `phi` is the AR(1) coefficient of the RR
    fluctuation: high phi -> strongly-correlated dynamics -> high DFA-α1; low phi
    -> uncorrelated -> low α1. If `phi_end` is set, phi interpolates from `phi` to
    `phi_end` across the ride (models a shared confound like heat lowering α1 over
    time). Injects `artifact_frac` ectopic/dropped beats and a respiratory
    (sinusoidal) modulation of amplitude resp_amp_ms."""
    n = len(hr_series)
    rr_by_second = [[] for _ in range(n)]
    t = 0.0
    fluct = 0.0
    sigma = 12.0
    while t < n:
        sec = int(t)
        if sec >= n:
            break
        hr = hr_series[sec]
        if hr is None or hr <= 0:
            t += 1.0
            continue
        phi_t = phi if phi_end is None else phi + (phi_end - phi) * (sec / n)
        base = 60000.0 / hr
        fluct = phi_t * fluct + math.sqrt(max(1e-6, 1 - phi_t * phi_t)) * rng.normal(0, sigma)
        resp = resp_amp_ms * math.sin(2 * math.pi * resp_hz * t) if resp_amp_ms > 0 else 0.0
        rr = base + fluct + resp
        if rng.random() < artifact_frac:
            rr *= rng.choice([0.55, 1.5])  # ectopic / missed beat
        rr = float(np.clip(rr, 300, 2000))
        t += rr / 1000.0
        end_sec = int(t)
        if 0 <= end_sec < n:
            rr_by_second[end_sec].append(rr)
    return rr_by_second


def _phi_for_intensity(power_frac_ftp):
    """Map intensity (fraction of FTP) to the RR-fluctuation AR(1) coefficient so
    mean DFA-α1 falls with intensity (Rogers/Gronwald direction): high phi (strong
    correlation -> high α1) when easy, near-white (low α1) near/above threshold.
    Wide, monotone; the harness only checks the ensemble direction."""
    p = float(np.clip(power_frac_ftp, 0.2, 1.4))
    return float(np.clip(0.95 - 1.05 * (p - 0.4), 0.05, 0.95))


# Fresh HR-power relation used to synthesize physiologically-consistent HR. Kept
# equal to the model's HR_ss defaults so a FRESH ride starts with F≈0 (no static
# offset masquerading as fatigue); imposed drift then rides on top of it.
FRESH_HR_REST = 50.0
FRESH_G_P = 0.45


def _fresh_hr(power_w, hr_rest=FRESH_HR_REST, g_p=FRESH_G_P, hr_max=190.0):
    return float(np.clip(hr_rest + g_p * power_w, hr_rest, hr_max))


def steady_ride(power_w=165.0, duration_s=3600, hr_drift_bpm=6.0,
                cadence=88.0, ftp=250.0, artifact_frac=0.005, resp_hz=0.25,
                seed=0, resp_amp_ms=0.0, hr_rest=FRESH_HR_REST, g_p=FRESH_G_P,
                alpha1_drift=0.0, label="steady") -> Ride:
    rng = np.random.default_rng(seed)
    power = [float(power_w + rng.normal(0, 3)) for _ in range(duration_s)]
    fresh = _fresh_hr(power_w, hr_rest, g_p)
    # HR = fresh HR for the power + imposed cardiac drift (the F signal) + noise
    hr = [float(fresh + hr_drift_bpm * (i / max(1, duration_s)) + rng.normal(0, 1.0))
          for i in range(duration_s)]
    cad = [float(cadence + rng.normal(0, 2)) for _ in range(duration_s)]
    phi = _phi_for_intensity(power_w / ftp)
    # alpha1_drift>0: RR correlation FALLS over the ride (α1 drifts down) — used to
    # model a shared confound (heat) that moves α1 as well as HR.
    phi_end = max(0.05, phi - alpha1_drift) if alpha1_drift > 0 else None
    rr = _rr_stream(hr, phi, artifact_frac, resp_hz, rng, resp_amp_ms, phi_end)
    return Ride(power, hr, cad, rr, label)


def intervals_ride(duration_s=3600, ftp=250.0, cp=240.0, seed=1,
                   label="intervals") -> Ride:
    """Hard interval ride: repeated efforts well above CP (feat-of-strength).
    HR relaxes toward the fresh HR for the current power (with lag)."""
    rng = np.random.default_rng(seed)
    power, hr, cad, hr_series = [], [], [], []
    hr_cur = _fresh_hr(ftp * 0.5)
    for i in range(duration_s):
        phase = i % 480
        if phase < 240:                      # 4 min hard @ ~1.3·CP
            p = cp * 1.3 + rng.normal(0, 8)
        else:                                # 4 min recovery
            p = ftp * 0.5 + rng.normal(0, 6)
        target = _fresh_hr(p)
        hr_cur += (target - hr_cur) * (1.0 / 30.0)   # 30 s HR lag toward fresh
        power.append(float(p))
        hr.append(float(hr_cur))
        cad.append(float(90 + rng.normal(0, 3)))
        hr_series.append(hr_cur)
    phi = _phi_for_intensity(1.1)
    rr = _rr_stream(hr_series, phi, 0.01, 0.3, rng)
    return Ride(power, hr, cad, rr, label)


def long_grind_ride(duration_s=7200, power_w=175.0, ftp=250.0,
                    hr_drift_bpm=14.0, seed=2, label="grind") -> Ride:
    """Long sub-threshold grind with strong cardiac drift (attrition)."""
    return steady_ride(power_w=power_w, duration_s=duration_s,
                       hr_drift_bpm=hr_drift_bpm, ftp=ftp, seed=seed, label=label)


def ramp_ride(duration_s=1200, ftp=250.0, hr0=100.0, seed=3, label="ramp") -> Ride:
    """Incremental ramp from easy to max — for the α1-vs-intensity direction."""
    rng = np.random.default_rng(seed)
    power, hr, cad, hr_series = [], [], [], []
    for i in range(duration_s):
        frac = 0.4 + 0.9 * (i / duration_s)      # 0.4 -> 1.3 FTP
        p = ftp * frac + rng.normal(0, 5)
        h = _fresh_hr(p)                          # fresh HR tracks the ramp
        power.append(float(p)); hr.append(float(h)); cad.append(float(88))
        hr_series.append(h)
    # RR correlation decreases as intensity climbs (per-second phi)
    rr_by_second = [[] for _ in range(duration_s)]
    t = 0.0; fluct = 0.0
    while t < duration_s:
        sec = int(t)
        if sec >= duration_s:
            break
        frac = 0.4 + 0.9 * (sec / duration_s)
        phi = _phi_for_intensity(frac)
        base = 60000.0 / hr_series[sec]
        fluct = phi * fluct + math.sqrt(max(1e-6, 1 - phi * phi)) * rng.normal(0, 12)
        rr = float(np.clip(base + fluct, 300, 2000))
        t += rr / 1000.0
        e = int(t)
        if 0 <= e < duration_s:
            rr_by_second[e].append(rr)
    return Ride(power, hr, cad, rr_by_second, label)


def heat_ride(duration_s=5400, power_w=175.0, ftp=250.0, seed=4, label="heat") -> Ride:
    """Hot-day ride: a SHARED confound that moves BOTH channels — extra cardiac
    drift (HR rises -> decoupling) AND falling RR correlation (α1 drifts down)."""
    return steady_ride(power_w=power_w, duration_s=duration_s, hr_drift_bpm=20.0,
                       ftp=ftp, seed=seed, alpha1_drift=0.35, label=label)


def drop_channel(ride: Ride, channel: str, start_s=0, end_s=None) -> Ride:
    """Return a copy of the ride with a sensor dropped over [start, end)."""
    end_s = len(ride.power) if end_s is None else end_s
    p = list(ride.power); h = list(ride.hr); c = list(ride.cadence)
    rr = [list(x) for x in ride.rr_by_second]
    for i in range(start_s, min(end_s, len(p))):
        if channel == "power":
            p[i] = None
        elif channel == "hr":
            h[i] = None
        elif channel == "cadence":
            c[i] = None
        elif channel == "rr":
            rr[i] = []
    return Ride(p, h, c, rr, ride.label + f"+drop_{channel}")


def corrupt_rr(ride: Ride, artifact_frac: float, seed=9) -> Ride:
    """Inject additional RR artifacts at a target fraction."""
    rng = np.random.default_rng(seed)
    rr = []
    for beats in ride.rr_by_second:
        nb = []
        for v in beats:
            if rng.random() < artifact_frac:
                v = v * rng.choice([0.5, 1.6])
            nb.append(float(v))
        rr.append(nb)
    return Ride(list(ride.power), list(ride.hr), list(ride.cadence), rr,
                ride.label + f"+art{int(artifact_frac*100)}")


# ---------------------------------------------------------------------------
# Real-file ingestion
# ---------------------------------------------------------------------------
def ingest_csv(path: str) -> Ride:
    """CSV columns (header, case-insensitive): time,power,hr,cadence,rr.
    `rr` may hold one or more RR values for that second, separated by '|'."""
    power, hr, cad, rr = [], [], [], []
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh)
        cols = {c.lower(): c for c in reader.fieldnames or []}

        def get(row, key):
            c = cols.get(key)
            if c is None or row[c] in (None, ""):
                return None
            return row[c]

        for row in reader:
            p = get(row, "power"); h = get(row, "hr"); cd = get(row, "cadence")
            power.append(float(p) if p is not None else None)
            hr.append(float(h) if h is not None else None)
            cad.append(float(cd) if cd is not None else None)
            rv = get(row, "rr")
            rr.append([float(x) for x in str(rv).split("|")] if rv else [])
    return Ride(power, hr, cad, rr, label=path)


def ingest_fit(path: str) -> Ride:
    """Optional FIT ingestion via `fitparse` (pip install fitparse). Raises a
    clear error if the dependency is missing so the harness can skip cleanly."""
    try:
        from fitparse import FitFile  # type: ignore
    except ImportError as exc:  # pragma: no cover
        raise RuntimeError(
            "FIT ingestion needs the optional 'fitparse' package "
            "(pip install fitparse); use ingest_csv for RR-bearing CSVs.") from exc
    fit = FitFile(path)
    power, hr, cad, rr = [], [], [], []
    pending_rr: List[float] = []
    for msg in fit.get_messages():
        name = msg.name
        if name == "hrv":
            for d in msg:
                if d.name == "time" and d.value is not None:
                    for v in (d.value if isinstance(d.value, (list, tuple)) else [d.value]):
                        if v is not None:
                            pending_rr.append(float(v) * 1000.0)
        elif name == "record":
            vals = {d.name: d.value for d in msg}
            power.append(vals.get("power"))
            hr.append(vals.get("heart_rate"))
            cad.append(vals.get("cadence"))
            rr.append(pending_rr)
            pending_rr = []
    return Ride(power, hr, cad, rr, label=path)
