#!/usr/bin/env python3
"""
Predictive/proactive autoscaling forecaster — Phase 3 POC.

WHAT THIS IS: a small script, run every few minutes by a Kubernetes CronJob,
that looks at ALB request-rate history and publishes a *forecasted*
desired-replica-count as a custom CloudWatch metric. KEDA's aws-cloudwatch
scaler reads that metric and scales the httpbin Deployment for the traffic
expected over the next few minutes, instead of only reacting after load has
already arrived (what a plain HPA does).

THE FORECAST (classical, explainable — deliberately not a trained model):
the demand expected over the next HORIZON_MINUTES is the largest of
  1. level     — the request rate right now (mean of the last few minutes),
  2. trend     — that level extrapolated HORIZON_MINUTES ahead along the
                 recent slope (catches a ramp that is already under way),
  3. seasonal  — the peak of the *same upcoming window one period ago*
                 (catches a ramp that hasn't started yet but happened at
                 this point in the cycle last time).
Taking the maximum biases toward scaling out early; scaling back in is left
to KEDA's cooldown, because briefly having a pod too many is cheaper than
being short during a ramp.

The seasonal term is what makes this *proactive*. The period is
SEASONAL_PERIOD_MINUTES: 1440 (daily) is the realistic setting, but for the
reactive-vs-proactive demo it's set to 60 so the HPA-baseline run of the k6
ramp becomes the "history" for the KEDA run an hour later (see README).

WHY CLOUDWATCH FOR HISTORY, NOT PROMETHEUS: go-httpbin exposes no /metrics
endpoint, so there's no in-cluster request-rate signal to scrape. The ALB
already publishes `RequestCount` to CloudWatch with zero instrumentation.

WHY THE ALB IS DISCOVERED AT RUNTIME: the ALB is created by the AWS Load
Balancer Controller from the Ingress (GitOps), not by Terraform, so its ARN
isn't known ahead of time. The Ingress pins a stable load-balancer-name;
this script resolves that name to today's CloudWatch dimension on every run.
"""
import datetime
import math
import os
import sys

REGION = os.environ.get("AWS_REGION", "us-east-1")
ALB_NAME = os.environ.get("ALB_NAME", "httpbin-public-alb")
CUSTOM_NAMESPACE = os.environ.get("CUSTOM_METRIC_NAMESPACE", "httpbin/predictive-scaling")
METRIC_NAME = os.environ.get("CUSTOM_METRIC_NAME", "DesiredReplicas")

# How many requests one pod comfortably handles per minute — a stated
# assumption, not a load-tested constant. Tune from your own load test.
REQUESTS_PER_POD_PER_MINUTE = int(os.environ.get("REQUESTS_PER_POD_PER_MINUTE", "300"))
MIN_REPLICAS = int(os.environ.get("MIN_REPLICAS", "2"))
MAX_REPLICAS = int(os.environ.get("MAX_REPLICAS", "20"))

HORIZON_MINUTES = int(os.environ.get("HORIZON_MINUTES", "10"))
SEASONAL_PERIOD_MINUTES = int(os.environ.get("SEASONAL_PERIOD_MINUTES", "1440"))
LEVEL_MINUTES = 3   # "now" = mean of the last 3 complete minutes
TREND_MINUTES = 10  # slope fitted over the last 10 minutes


# ---------------------------------------------------------------------------
# Pure forecasting logic (no AWS calls) — unit-tested in test_forecast.py.
# A series is a list of per-minute request counts, oldest first.
# ---------------------------------------------------------------------------
def level(recent):
    window = recent[-LEVEL_MINUTES:]
    return sum(window) / len(window) if window else 0.0


def slope(recent):
    """Least-squares slope (requests/min per minute) over the trend window."""
    ys = recent[-TREND_MINUTES:]
    n = len(ys)
    if n < 2:
        return 0.0
    mean_x = (n - 1) / 2
    mean_y = sum(ys) / n
    num = sum((x - mean_x) * (y - mean_y) for x, y in enumerate(ys))
    den = sum((x - mean_x) ** 2 for x in range(n))
    return num / den


def forecast_rpm(recent, seasonal_ahead, horizon=HORIZON_MINUTES):
    """Expected peak requests/minute over the next `horizon` minutes."""
    now_level = level(recent)
    trend = now_level + max(0.0, slope(recent)) * horizon
    seasonal = max(seasonal_ahead) if seasonal_ahead else 0.0
    return max(now_level, trend, seasonal)


def desired_replicas(rpm, per_pod=REQUESTS_PER_POD_PER_MINUTE,
                     min_replicas=MIN_REPLICAS, max_replicas=MAX_REPLICAS):
    wanted = math.ceil(rpm / per_pod) if rpm > 0 else min_replicas
    return max(min_replicas, min(max_replicas, wanted))


# ---------------------------------------------------------------------------
# AWS I/O
# ---------------------------------------------------------------------------
def resolve_alb_dimension(elbv2_client):
    """Fixed ALB name -> today's CloudWatch dimension value ('app/<name>/<id>')."""
    resp = elbv2_client.describe_load_balancers(Names=[ALB_NAME])
    lbs = resp.get("LoadBalancers", [])
    if not lbs:
        raise RuntimeError(f"No load balancer named '{ALB_NAME}' — has the Ingress synced yet?")
    arn = lbs[0]["LoadBalancerArn"]
    # arn:aws:elasticloadbalancing:<region>:<acct>:loadbalancer/app/<name>/<id>
    return "/".join(arn.split("/")[-3:])


def fetch_per_minute(cw_client, dimension_value, start, end):
    """Per-minute RequestCount between start and end, oldest first.

    CloudWatch omits minutes with no requests, so missing minutes are filled
    with 0 rather than silently shortening the series."""
    resp = cw_client.get_metric_data(
        MetricDataQueries=[{
            "Id": "requests",
            "MetricStat": {
                "Metric": {
                    "Namespace": "AWS/ApplicationELB",
                    "MetricName": "RequestCount",
                    "Dimensions": [{"Name": "LoadBalancer", "Value": dimension_value}],
                },
                "Period": 60,
                "Stat": "Sum",
            },
        }],
        StartTime=start,
        EndTime=end,
    )
    result = resp["MetricDataResults"][0]
    by_minute = {ts.replace(second=0, microsecond=0): v
                 for ts, v in zip(result["Timestamps"], result["Values"])}
    minutes = int((end - start).total_seconds() // 60)
    return [by_minute.get(start + datetime.timedelta(minutes=i), 0.0) for i in range(minutes)]


def main():
    import boto3  # imported here so the pure functions can be tested without boto3

    session = boto3.Session(region_name=REGION)
    cw = session.client("cloudwatch")
    elbv2 = session.client("elbv2")

    # Work on whole minutes, and skip the current (still-filling) minute.
    now = datetime.datetime.now(datetime.timezone.utc).replace(second=0, microsecond=0)
    dim = resolve_alb_dimension(elbv2)

    recent = fetch_per_minute(cw, dim, now - datetime.timedelta(minutes=TREND_MINUTES), now)
    past = now - datetime.timedelta(minutes=SEASONAL_PERIOD_MINUTES)
    seasonal_ahead = fetch_per_minute(cw, dim, past, past + datetime.timedelta(minutes=HORIZON_MINUTES))

    rpm = forecast_rpm(recent, seasonal_ahead)
    desired = desired_replicas(rpm)

    print(f"[{now.isoformat()}] level={level(recent):.0f}rpm slope={slope(recent):.1f} "
          f"seasonal_peak={max(seasonal_ahead, default=0):.0f}rpm (period={SEASONAL_PERIOD_MINUTES}m) "
          f"-> forecast={rpm:.0f}rpm over next {HORIZON_MINUTES}m -> desired_replicas={desired}")

    cw.put_metric_data(
        Namespace=CUSTOM_NAMESPACE,
        MetricData=[{
            "MetricName": METRIC_NAME,
            "Dimensions": [{"Name": "Service", "Value": "httpbin"}],
            "Value": float(desired),
            "Unit": "Count",
        }],
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 — CronJob: log and exit non-zero
        print(f"predictive-scaler FAILED: {exc}", file=sys.stderr)
        sys.exit(1)
