"""Real-file ingestion smoke test: a CSV with power/HR/cadence/RR drives the
engine end-to-end without crashing and produces bounded AFI."""
import math
import os

from fatiguemeter import model as M, signals as S
from fatiguemeter.engine import RideEngine

DATA = os.path.join(os.path.dirname(__file__), "data", "sample_ride.csv")


def test_csv_ingestion_runs():
    ride = S.ingest_csv(DATA)
    assert len(ride.power) == 120
    assert any(rr for rr in ride.rr_by_second)   # RR parsed
    out = RideEngine(M.Config()).run(ride.power, ride.hr, ride.cadence, ride.rr_by_second)
    assert not out.nan_seen
    assert all(0.0 <= a <= 100.0 and math.isfinite(a) for a in out.afi)
