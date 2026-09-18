#!/usr/bin/env python3
"""
Predictive/proactive autoscaling forecaster — Phase 3 POC.

WHAT THIS IS: a small script, run every few minutes by a Kubernetes CronJob,
that looks at recent ALB request-rate history and publishes a *forecasted*
desired-replica-count as a custom CloudWatch metric. KEDA's aws-cloudwatch
scaler then reads that metric and scales the httpbin Deployment ahead of the
traffic it expects, instead of only reacting after load has already arrived
(what a plain HPA does).

WHAT THIS DELIBERATELY IS NOT: a trained ML model. The "forecast" is
classical time-series smoothing — a weighted moving average with a
same-time-yesterday seasonal nudge. That's an honest, defensible choice for
a POC: it's cheap, explainable in one sentence, and good enough to
demonstrate the *mechanism* (proactive vs reactive scaling), which is the
actual point of this exercise. A real predictive-scaling system in
production would likely use Amazon Forecast, or a proper trained model —
described here as a named next step, not implemented.

WHY CLOUDWATCH FOR HISTORY, NOT PROMETHEUS: go-httpbin exposes no /metrics
endpoint (see main README), so there's no in-cluster request-rate signal to
scrape. The ALB, however, already publishes `RequestCount` to CloudWatch
(AWS/ApplicationELB namespace) with zero extra instrumentation — so that's
the source of truth here.

WHY THE ALB IS DISCOVERED AT RUNTIME, NOT PASSED IN AS A TERRAFORM OUTPUT:
the ALB itself is created by the AWS Load Balancer Controller reconciling
the Ingress (see k8s/ingress-public.yaml), not by Terraform — Terraform
never sees its ARN. But the ingress pins a stable
`alb.ingress.kubernetes.io/load-balancer-name`, so this script resolves that
fixed name to today's ARN (and CloudWatch dimension) via the AWS API on
every run — the correct way to bridge a GitOps-created resource back into
an AWS API call, without hardcoding an ARN that would go stale on ALB
recreation.
"""
import datetime
import math
import os
import sys

import boto3

REGION = os.environ.get("AWS_REGION", "us-east-1")
ALB_NAME = os.environ.get("ALB_NAME", "httpbin-public-alb")
CUSTOM_NAMESPACE = os.environ.get("CUSTOM_METRIC_NAMESPACE", "httpbin/predictive-scaling")
METRIC_NAME = os.environ.get("CUSTOM_METRIC_NAME", "DesiredReplicas")

# How many requests one pod comfortably handles per minute — a rough,
# stated assumption, not a load-tested constant. Tune this from your own
# load test (see predictive-scaling/loadtest/ in the study guide) before
# trusting the numbers this produces.
REQUESTS_PER_POD_PER_MINUTE = int(os.environ.get("REQUESTS_PER_POD_PER_MINUTE", "300"))
MIN_REPLICAS = int(os.environ.get("MIN_REPLICAS", "2"))
MAX_REPLICAS = int(os.environ.get("MAX_REPLICAS", "20"))

LOOKBACK_MINUTES = 60          # recent window used for the moving average
SEASONAL_LOOKBACK_HOURS = 24   # how far back to look for "same time yesterday"
FORECAST_HORIZON_MINUTES = 10  # how far ahead we're forecasting for


def resolve_alb_dimension(elbv2_client) -> str:
    """Resolve the fixed ALB name to today's CloudWatch dimension value
    ('app/<name>/<id>'), since the ALB is GitOps-managed and its ARN isn't
    known to Terraform."""
    resp = elbv2_client.describe_load_balancers(Names=[ALB_NAME])
    lbs = resp.get("LoadBalancers", [])
    if not lbs:
        raise RuntimeError(f"No load balancer found named '{ALB_NAME}' — has the Ingress synced yet?")
    arn = lbs[0]["LoadBalancerArn"]
    # arn:aws:elasticloadbalancing:<region>:<acct>:loadbalancer/app/<name>/<id>
    return "/".join(arn.split("/")[-3:])


def fetch_request_count(cw_client, dimension_value: str, start, end):
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
    values = resp["MetricDataResults"][0]["Values"]
    timestamps = resp["MetricDataResults"][0]["Timestamps"]
    # CloudWatch returns newest-first; sort oldest-first for a clean series.
    series = sorted(zip(timestamps, values))
    return [v for _, v in series]


def weighted_moving_average(series):
    """Linearly weight recent minutes more heavily than older ones."""
    if not series:
        return 0.0
    weights = list(range(1, len(series) + 1))
    return sum(v * w for v, w in zip(series, weights)) / sum(weights)


def forecast_requests_per_minute(cw_client, elbv2_client, now) -> float:
    dim = resolve_alb_dimension(elbv2_client)

    recent = fetch_request_count(
        cw_client, dim,
        start=now - datetime.timedelta(minutes=LOOKBACK_MINUTES),
        end=now,
    )
    baseline = weighted_moving_average(recent)

    # Seasonal nudge: if we have data from ~this time yesterday, blend it in.
    # This is what lets the forecast anticipate a *known, recurring* ramp
    # (e.g. a daily traffic pattern) instead of only extrapolating the last
    # hour — the thing a plain reactive HPA structurally can't do.
    seasonal_start = now - datetime.timedelta(hours=SEASONAL_LOOKBACK_HOURS, minutes=LOOKBACK_MINUTES // 2)
    seasonal_end = now - datetime.timedelta(hours=SEASONAL_LOOKBACK_HOURS - (LOOKBACK_MINUTES // 2) / 60)
    try:
        seasonal = fetch_request_count(cw_client, dim, seasonal_start, seasonal_end)
        seasonal_avg = weighted_moving_average(seasonal) if seasonal else None
    except Exception:
        seasonal_avg = None

    if seasonal_avg and seasonal_avg > 0:
        forecast = 0.6 * baseline + 0.4 * seasonal_avg
    else:
        forecast = baseline

    return forecast


def main():
    session = boto3.Session(region_name=REGION)
    cw = session.client("cloudwatch")
    elbv2 = session.client("elbv2")

    now = datetime.datetime.utcnow()
    forecast_rpm = forecast_requests_per_minute(cw, elbv2, now)

    desired = math.ceil(forecast_rpm / REQUESTS_PER_POD_PER_MINUTE) if forecast_rpm > 0 else MIN_REPLICAS
    desired = max(MIN_REPLICAS, min(MAX_REPLICAS, desired))

    print(f"[{now.isoformat()}Z] forecast_rpm={forecast_rpm:.1f} "
          f"requests_per_pod_per_min={REQUESTS_PER_POD_PER_MINUTE} -> desired_replicas={desired}")

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
    except Exception as exc:  # noqa: BLE001 — CronJob: log and exit non-zero, don't crash-loop silently
        print(f"predictive-scaler FAILED: {exc}", file=sys.stderr)
        sys.exit(1)
