import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '5s', target: 5 },     // normal dulu
    { duration: '5s', target: 100 },   // lonjakan tiba-tiba
    { duration: '20s', target: 100 },  // tahan di puncak
    { duration: '10s', target: 5 },    // turun lagi
  ],
};

export default function () {
  const res = http.get('http://10.10.10.10/health');
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
  sleep(0.3);
}
