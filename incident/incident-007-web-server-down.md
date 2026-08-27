# Incident 007 — Web Server Down (web-01)

## Summary
Simulasi terkontrol untuk membuktikan kemampuan High Availability pada Load Balancer `lb-01` (HAProxy). Service Nginx di `web-01` dihentikan secara sengaja untuk mengamati apakah HAProxy dapat mendeteksi kegagalan backend dan melakukan failover otomatis ke `web-02`, tanpa downtime yang terlihat oleh client.

## Impact
- **Scope**: Hanya `web-01` yang terdampak (down secara sengaja).
- **User-facing impact**: Tidak ada — traffic client tetap terlayani penuh oleh `web-02` selama `web-01` down, karena HAProxy mengeluarkan `web-01` dari rotasi backend secara otomatis.
- **Severity**: Low (simulasi terkontrol, bukan insiden produksi nyata).

## Detection
Deteksi dilakukan melalui dua jalur:
1. **HAProxy health check** — `option httpchk GET /` mengirim HTTP request berkala ke setiap backend. Ketika `web-01` berhenti merespons, HAProxy menandai backend tersebut **DOWN** pada beberapa health check gagal berturut-turut.
2. **Verifikasi visual** — dashboard statistik HAProxy (`http://10.10.10.10:8404/stats`) menunjukkan baris `web01` berubah dari hijau (UP) menjadi merah (DOWN).

## Investigation
Langkah investigasi yang dilakukan (simulasi, root cause sudah diketahui karena disengaja):
```bash
# Di web-01
sudo systemctl status nginx
```
Konfirmasi: Nginx dalam status `inactive (dead)` setelah dihentikan manual.

Dari sisi `lb-01`, dashboard stats dan log HAProxy dicek untuk mengonfirmasi backend `web01` benar-benar dikeluarkan dari rotasi:
```bash
sudo systemctl status haproxy
curl -I http://10.10.10.10
```
Pada langkah ini, refresh berulang terhadap `http://10.10.10.10` hanya menampilkan halaman "Hello from web-02" — bukti bahwa traffic 100% dialihkan.

## Root Cause
Service Nginx dihentikan secara sengaja di `web-01` melalui:
```bash
sudo systemctl stop nginx
```
Tujuannya murni simulasi (bukan kegagalan nyata) untuk menguji mekanisme failover Load Balancer.

## Resolution
Nginx dinyalakan kembali di `web-01`:
```bash
sudo systemctl start nginx
```
HAProxy mendeteksi backend kembali sehat pada health check berikutnya dan otomatis memasukkan `web01` kembali ke rotasi round-robin.

## Verification
1. Dashboard stats HAProxy (`/stats`) menunjukkan baris `web01` kembali hijau (UP).
2. Refresh berulang terhadap `http://10.10.10.10` kembali menampilkan halaman bergantian antara "Hello from web-01" dan "Hello from web-02", konsisten dengan perilaku round-robin normal.
3. Tidak ada intervensi manual lain yang diperlukan — seluruh siklus failover dan recovery berjalan otomatis oleh HAProxy.

## Preventive Action
- Pertimbangkan menurunkan interval health check default HAProxy (`inter`) agar deteksi kegagalan backend lebih cepat di lingkungan production-like berikutnya.
- Tambahkan alerting (Phase 5 — Monitoring) agar tim mendapat notifikasi otomatis saat backend down, bukan hanya terlihat lewat dashboard stats.
- Dokumentasikan threshold jumlah backend minimum yang harus tetap UP sebelum dianggap kondisi kritis (misalnya: dengan 2 backend, kehilangan 1 backend = warning, kehilangan keduanya = critical/full outage).

## Lessons Learned
- **Health check adalah fondasi HA** — tanpa `option httpchk`, HAProxy tidak akan tahu backend mana yang sehat, dan traffic tetap dikirim ke backend yang mati (menyebabkan error di sisi client).
- **Load Balancer menyembunyikan kegagalan backend individual dari client** — ini nilai utama arsitektur HA: kegagalan satu komponen tidak berarti kegagalan layanan secara keseluruhan.
- Failover dan recovery di lab ini berjalan **tanpa intervensi manual apa pun** di sisi `lb-01` — cukup memperbaiki backend yang bermasalah, sistem secara otomatis menyesuaikan rotasi.
