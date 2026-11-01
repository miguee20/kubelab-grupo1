// Load test for the HorizontalPodAutoscaler demo (HA-05).
// Run from any machine that resolves api.grupo1.lab (instructor laptop over Tailscale):
//   k6 run tests/load/k6-api.js
//   k6 run -e BASE_URL=http://api.grupo1.lab -e PEAK=60 tests/load/k6-api.js
// While it runs:  kubectl -n inventory get hpa api -w
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://api.grupo1.lab';
const PEAK = Number(__ENV.PEAK || 40);

export const options = {
  stages: [
    { duration: '30s', target: Math.round(PEAK / 4) }, // warm up
    { duration: '4m', target: PEAK },                  // sustained load -> HPA scales out
    { duration: '1m', target: 0 },                     // ramp down -> HPA scales back in
  ],
  thresholds: {
    http_req_failed: ['rate<0.05'],     // less than 5 % errors while pods are added
    http_req_duration: ['p(95)<2000'],
  },
};

export default function () {
  const list = http.get(`${BASE_URL}/products`);
  check(list, { 'list products 200': (r) => r.status === 200 });

  const one = http.get(`${BASE_URL}/products/1`);
  check(one, { 'get product 200/404': (r) => r.status === 200 || r.status === 404 });

  sleep(0.1);
}
