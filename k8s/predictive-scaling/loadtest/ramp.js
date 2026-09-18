// k6 load test with a predictable, repeatable ramp — the exact kind of
// pattern proactive/predictive scaling is supposed to shine on, since a
// forecast needs *some* regularity to anticipate.
//
// Run from GitHub Codespaces (or anywhere with network access to the
// internet-facing ALB):
//   k6 run -e TARGET_URL=https://<your-domain-or-alb-dns>/get ramp.js
//
// Run this TWICE with identical parameters — once against the reactive HPA
// baseline, once against the KEDA ScaledObject — and compare the two
// Grafana screenshots. That comparison, not the script, is the artifact.
import http from 'k6/http';
import { sleep } from 'k6';

const TARGET_URL = __ENV.TARGET_URL || 'https://CHANGE-ME/get';

export const options = {
  scenarios: {
    predictable_ramp: {
      executor: 'ramping-arrival-rate',
      startRate: 5,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 200,
      stages: [
        { target: 5, duration: '2m' },    // quiet baseline
        { target: 100, duration: '5m' },  // steady, predictable ramp up
        { target: 100, duration: '5m' },  // sustained peak
        { target: 5, duration: '3m' },    // ramp back down
      ],
    },
  },
};

export default function () {
  http.get(TARGET_URL);
  sleep(0.1);
}
