"""Unit tests for the forecaster's pure logic (stdlib only, no AWS).

Run:  python -m unittest discover -s k8s/predictive-scaling -v
"""
import math
import unittest

import forecast as f


def k6_ramp_rpm(t):
    """Requests/minute at minute t of loadtest/ramp.js (5 -> 100 rps)."""
    if t < 2:
        rps = 5
    elif t < 7:
        rps = 5 + 95 * (t - 2) / 5
    elif t < 12:
        rps = 100
    elif t < 15:
        rps = 100 - 95 * (t - 12) / 3
    else:
        rps = 5
    return rps * 60


def pods_needed(t):
    return f.desired_replicas(k6_ramp_rpm(t))


class PureFunctions(unittest.TestCase):
    def test_flat_traffic_holds_steady(self):
        self.assertAlmostEqual(f.forecast_rpm([600.0] * 10, [600.0] * 10), 600.0)

    def test_rising_trend_projects_ahead(self):
        recent = [100.0 * i for i in range(10)]  # +100 rpm every minute
        self.assertGreater(f.forecast_rpm(recent, []), f.level(recent))

    def test_falling_trend_never_forecasts_below_level(self):
        recent = [1000.0 - 100 * i for i in range(10)]
        self.assertEqual(f.forecast_rpm(recent, []), f.level(recent))

    def test_seasonal_peak_anticipates_unstarted_ramp(self):
        quiet_now = [300.0] * 10
        ramp_last_period = [300.0, 1500.0, 3000.0, 6000.0]
        self.assertEqual(f.forecast_rpm(quiet_now, ramp_last_period), 6000.0)

    def test_replicas_are_clamped(self):
        self.assertEqual(f.desired_replicas(0), f.MIN_REPLICAS)
        self.assertEqual(f.desired_replicas(10 ** 9), f.MAX_REPLICAS)
        self.assertEqual(f.desired_replicas(3001, per_pod=300, min_replicas=1, max_replicas=50), 11)

    def test_missing_history_is_safe(self):
        self.assertEqual(f.forecast_rpm([], []), 0.0)


class ReplayK6Ramp(unittest.TestCase):
    """Replays the demo: the HPA-baseline run is last period's history, and
    the forecaster runs every 5 minutes (the CronJob schedule) during the
    KEDA run. Asserts the published replica count is never short of demand
    over the next horizon, i.e. it scales *ahead* of the ramp."""

    def test_forecast_covers_demand_ahead(self):
        horizon = f.HORIZON_MINUTES
        for run_at in range(-10, 25, 5):
            recent = [k6_ramp_rpm(m) for m in range(run_at - f.TREND_MINUTES, run_at)]
            seasonal_ahead = [k6_ramp_rpm(m) for m in range(run_at, run_at + horizon)]
            published = f.desired_replicas(f.forecast_rpm(recent, seasonal_ahead))
            # It must cover demand until the next CronJob run (5 min later).
            peak_until_next_run = max(pods_needed(m) for m in range(run_at, run_at + 5))
            self.assertGreaterEqual(
                published, peak_until_next_run,
                f"run at t={run_at}m published {published}, needed {peak_until_next_run}")

    def test_without_history_it_still_tracks_the_ramp(self):
        # No seasonal data (first ever run): trend term alone must react
        # at least as fast as current demand.
        for run_at in range(0, 15, 5):
            recent = [k6_ramp_rpm(m) for m in range(run_at - f.TREND_MINUTES, run_at)]
            published = f.desired_replicas(f.forecast_rpm(recent, []))
            self.assertGreaterEqual(published, pods_needed(run_at - 1))


if __name__ == "__main__":
    unittest.main()
