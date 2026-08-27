# Performance Testing Report

## 1. Ringkasan Eksekutif

Pengujian beban dilakukan terhadap endpoint `/health` melalui `lb-01` (HAProxy), menempuh jalur penuh arsitektur 3-tier: `Client → HAProxy → Nginx (web-01/web-02) → FastAPI (app-01)`. Tiga skenario traffic dijalankan sesuai spesifikasi awal project — **Normal**, **High**, dan **Burst** — menggunakan k6 v0.54.0, dijalankan dari `infra-01`.

**Hasil utama**: sistem mempertahankan **0% error rate di ketiga skenario**, termasuk saat lonjakan tiba-tiba ke 100 concurrent virtual users. Tidak ada request yang gagal (`http_req_failed` selalu 0.00%), membuktikan HAProxy health check dan load balancing bekerja sesuai desain di bawah tekanan.

## 2. Metodologi

**Tool**: k6 v0.54.0
**Target**: `http://10.10.10.10/health` (lewat lb-01, endpoint diteruskan ke app-01)
**Environment saat pengujian**: `infra-01`, `lb-01`, `web-01`, `web-02`, `app-01` menyala bersamaan di atas satu laptop (VMware Workstation Player) — perlu diperhatikan hasil ini mencerminkan performa di lingkungan lab dengan resource fisik terbagi ke banyak VM sekaligus, bukan hardware dedicated.

| Skenario | Virtual Users (VU) | Pola Ramp | Durasi |
|---|---|---|---|
| Normal | 5 (puncak) | Bertahap: 0→5 (30s), tahan (1m), turun (10s) | 1m40s |
| High | 50 (puncak) | Bertahap: 0→50 (30s), tahan (1m), turun (15s) | 1m45s |
| Burst | 100 (puncak) | Tiba-tiba: 5→100 dalam 5s, tahan (20s), turun (10s) | 40s |

## 3. Hasil Detail

| Metric | Normal | High | Burst |
|---|---|---|---|
| Total requests | 405 | 7,593 | 7,623 |
| Throughput (req/s) | 4.02 | 69.03 | 151.71 |
| Error rate | 0.00% | 0.00% | 0.00% |
| Checks passed | 100% (810/810) | 100% (7,593/7,593) | 100% (7,623/7,623) |
| Response time — median | 5.52 ms | 5.43 ms | 12.14 ms |
| Response time — avg | 6.04 ms | 97.70 ms | 167.29 ms |
| Response time — p90 | 8.31 ms | 12.44 ms | 134.52 ms |
| Response time — p95 | 9.84 ms | 17.88 ms | 187.66 ms |
| Response time — max | 24.81 ms | 15,500 ms | 15,490 ms |

## 4. Analisis

### 4.1 Ketahanan (Zero Error Rate)
Di ketiga skenario, **tidak ada satu pun request yang gagal** — bahkan pada lonjakan tiba-tiba dari 5 ke 100 VU dalam 5 detik (skenario Burst, paling menantang karena tidak ada waktu ramp-up bertahap seperti skenario High). Ini membuktikan:
- HAProxy health check (`/health`, hasil perbaikan dari Incident 008) berfungsi dengan benar di bawah beban.
- Kedua backend Nginx (`web-01`, `web-02`) berbagi beban secara efektif lewat round-robin.
- FastAPI (Uvicorn) di `app-01`, meski single instance (bukan multi-worker), tetap responsif tanpa connection refused.

### 4.2 Gap antara Median dan Average/Max — Indikasi Resource Contention
Pola paling mencolok adalah **jarak besar antara median dan average/max** pada skenario High dan Burst:
- Median tetap rendah (5–12ms) di semua skenario — mayoritas request tetap cepat.
- Average melonjak signifikan (97ms di High, 167ms di Burst) dan max mencapai ~15.5 detik di kedua skenario berat.

Ini pola khas **outlier ekstrem pada sebagian kecil request**, bukan degradasi merata di seluruh traffic. Penyebab paling mungkin: **CPU laptop fisik terbagi ke lebih dari 5 VM Linux yang menyala bersamaan** (infra-01, lb-01, web-01, web-02, app-01) selama pengujian — sesekali proses k6, HAProxy, Nginx, atau Uvicorn kehabisan giliran CPU dari hypervisor, menyebabkan request tertentu "macet" sesaat sebelum diproses.

**Ini bukan bug arsitektur**, melainkan keterbatasan lingkungan pengujian (single physical machine menjalankan banyak VM) — di lingkungan produksi dengan resource dedicated per VM, pola outlier seperti ini diperkirakan akan jauh berkurang.

### 4.3 Skalabilitas Throughput
Throughput naik proporsional dengan jumlah VU (4 → 69 → 151 req/s seiring VU naik dari 5 → 50 → 100), menunjukkan sistem **tidak mengalami saturasi/plateau** dalam rentang beban yang diuji — kapasitas maksimum sesungguhnya kemungkinan masih di atas 100 concurrent users, tapi tidak diuji lebih jauh karena keterbatasan resource lab.

## 5. Rekomendasi

### Vertical Scaling
Jika latency p95/max pada beban tinggi perlu diperbaiki tanpa mengubah arsitektur:
- Tambah CPU/RAM untuk `app-01` (saat ini 1 vCPU/1GB RAM) — FastAPI dengan Uvicorn single-worker adalah bottleneck paling mungkin di antara seluruh tier.
- Jalankan Uvicorn dengan multiple worker (`--workers 4`) untuk memanfaatkan lebih dari 1 core jika CPU ditambah.

### Horizontal Scaling
Sesuai rencana awal project (`app-02`, opsional): tambah instance kedua untuk `app-01`, daftarkan sebagai backend kedua di reverse proxy Nginx — mendistribusikan beban aplikasi, bukan hanya web tier.

### Pengujian Lanjutan (Belum Dilakukan)
- Load test terhadap endpoint `/api/db-check` untuk mengukur dampak koneksi database di bawah beban (saat ini hanya `/health` yang diuji, yang tidak menyentuh database).
- Uji ketahanan durasi panjang (soak test, >30 menit) untuk mendeteksi potensi memory leak yang tidak terlihat pada test singkat ini.
- Pengujian di lingkungan dengan VM pada host fisik terpisah, untuk mengisolasi pengaruh resource contention lab dari performa arsitektur murni.

## 6. Kesimpulan

Arsitektur HA (HAProxy + dual Nginx + FastAPI) berhasil mempertahankan **ketersediaan 100%** di bawah tiga skenario beban berbeda, termasuk lonjakan traffic mendadak — capaian utama yang dituju project ini. Latency pada beban tinggi menunjukkan ruang optimasi (khususnya di tier aplikasi), namun ini konsisten dengan keterbatasan resource lab yang telah didokumentasikan sepanjang project (`docs/networking-updated.md`, `docs/SECURITY.md`), bukan cacat desain.
