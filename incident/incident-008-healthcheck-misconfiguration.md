# Incident 008 — HAProxy Health Check Misconfiguration

## Summary
Setelah `web-01` dan `web-02` diubah dari sekadar serve halaman statis menjadi reverse proxy ke `app-01` (Phase 4), HAProxy di `lb-01` mulai menandai kedua backend sebagai **DOWN**, menyebabkan `503 Service Unavailable` untuk semua traffic client, meski Nginx dan FastAPI di baliknya berjalan normal.

## Impact
- **Scope**: Seluruh traffic HTTP lewat `lb-01` terdampak — 100% request client gagal (503).
- **Severity**: High (bukan simulasi, ditemukan organik saat verifikasi end-to-end pertama kali setelah integrasi web-app).
- **Durasi**: Beberapa menit, dari saat pertama kali `curl` ke `lb-01` gagal sampai root cause ditemukan dan diperbaiki.

## Detection
`curl http://localhost/health` dari `lb-01` mengembalikan `503 Service Unavailable`. Dashboard stats HAProxy (`/stats`) menunjukkan kedua backend `web01` dan `web02` berstatus **DOWN**.

## Investigation
```bash
curl -I http://localhost/
```
dijalankan langsung di `web-01`, mengembalikan `404 Not Found`. Konfigurasi HAProxy diperiksa:
```
option httpchk GET /
```
Health check HAProxy secara default memeriksa path `/`, tapi setelah Nginx diubah menjadi reverse proxy murni ke FastAPI, tidak ada route yang terdaftar untuk path `/` di aplikasi (`main.py` hanya mendefinisikan `/health`, `/api/status`, `/api/users`, `/api/metrics`) — sehingga request ke `/` diteruskan ke FastAPI dan mendapat `404`.

## Root Cause
HAProxy health check mengecek path `/` yang tidak pernah didefinisikan sebagai endpoint di aplikasi backend, sehingga health check selalu gagal (`L7STS/404`) meski service sesungguhnya sehat.

## Resolution
```bash
sudo sed -i 's#option httpchk GET /#option httpchk GET /health#' /etc/haproxy/haproxy.cfg
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl restart haproxy
```
Health check diarahkan ke `/health`, endpoint yang memang didefinisikan dan selalu mengembalikan `200 OK` selama aplikasi hidup.

## Verification
Dashboard stats HAProxy menunjukkan kedua backend kembali **UP** dalam beberapa detik setelah restart. `curl http://localhost/health` dan `curl http://localhost/api/db-check` melalui `lb-01` kembali mengembalikan response normal dari aplikasi.

## Preventive Action
- Setiap kali endpoint default (`/`) suatu service diubah atau dihapus, health check yang bergantung padanya (load balancer, monitoring, orchestrator) harus diperbarui secara bersamaan sebagai satu perubahan, bukan dua langkah terpisah.
- Pertimbangkan menstandarkan seluruh aplikasi di lab ini untuk selalu menyediakan endpoint `/health` sejak awal desain, dan menjadikannya konvensi wajib untuk semua service baru.

## Lessons Learned
Health check yang sukses secara *teknis* (dapat response HTTP apa pun) tidak sama dengan health check yang *benar* — status code yang diperiksa harus eksplisit dicocokkan dengan endpoint yang benar-benar merepresentasikan kesehatan aplikasi. Insiden ini juga menegaskan pentingnya verifikasi end-to-end setelah perubahan arsitektur (statis → reverse proxy), bukan hanya menguji komponen secara terisolasi.
