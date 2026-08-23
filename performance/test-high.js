import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 50 },
    { duration: '1m', target: 50 },
    { duration: '15s', target: 0 },
  ],
};

export default function () {
  const res = http.get('http://10.10.10.10/health');
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
  sleep(0.5);
}
