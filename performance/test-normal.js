import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 5 },   // ramp up ke 5 virtual users
    { duration: '1m', target: 5 },    // stay di 5 users selama 1 menit
    { duration: '10s', target: 0 },   // ramp down
  ],
};

export default function () {
  const res = http.get('http://10.10.10.10/health');
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  sleep(1);
}
