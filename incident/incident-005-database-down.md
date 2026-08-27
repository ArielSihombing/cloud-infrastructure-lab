# Incident 005 — Database Down (Simulation Runbook)

> **Status**: Runbook siap-eksekusi. Jalankan saat `db-01` dan `app-01` menyala bersamaan.

## Summary
Simulasi kegagalan PostgreSQL untuk menguji deteksi, dampak berjenjang ke aplikasi (`/api/db-check`), dan proses recovery — termasuk opsi restore dari backup yang sudah dibangun di Phase 9.

## Simulation Steps

**1. Konfirmasi baseline:**
```bash
curl http://10.10.20.21:8000/api/db-check
sudo systemctl status postgresql
```

**2. Hentikan PostgreSQL secara sengaja:**
```bash
sudo systemctl stop postgresql
```

**3. Deteksi:**
```bash
curl http://10.10.20.21:8000/api/db-check
```
Response harus berubah dari `"database":"connected"` menjadi `"database":"error"` dengan detail koneksi gagal — mengonfirmasi aplikasi **fail gracefully** (tidak crash total, error informatif), pola yang sudah terbukti di Incident 006 (aplikasi tetap merespons `/health` normal meski `/api/db-check` gagal).

**4. Investigasi:**
```bash
sudo systemctl status postgresql
sudo journalctl -u postgresql -n 30 --no-pager
sudo tail -30 /var/log/postgresql/postgresql-14-main.log
```

**5. Resolusi:**
```bash
sudo systemctl start postgresql
sudo systemctl status postgresql
```

**6. Verifikasi:**
```bash
curl http://10.10.20.21:8000/api/db-check
```
Harus kembali `"database":"connected"`.

## Skenario Lanjutan — Restore dari Backup (Jika Data Corrupt, Bukan Sekadar Service Down)
Jika simulasi diperluas ke skenario data hilang (bukan cuma service berhenti):
```bash
# Dari infra-01
zcat ~/backups/database/labapp_<timestamp>.sql.gz | ssh ariel@10.10.20.31 "PGPASSWORD=ariel psql -h localhost -U labuser labapp"
```
Prosedur ini sudah didokumentasikan lengkap di `docs/backup-recovery.md`.

## Expected Root Cause
Simulasi murni (service dihentikan manual) — representasi skenario nyata: PostgreSQL crash karena OOM, corrupt data file, atau kehabisan disk (lihat Incident 002).

## Preventive Action (berlaku umum)
- Backup harian PostgreSQL sudah terjadwal (cron `30 2 * * *`) sejak Phase 9, memberi fallback jika restart service saja tidak cukup.
- Endpoint `/api/db-check` di aplikasi (dibangun sejak Phase 4) berfungsi sebagai health check tidak langsung untuk database — bisa dijadikan dasar alert tambahan di Grafana/Prometheus (belum diimplementasikan, lihat Future Improvements di README utama).

## Actual Result
_(Isi setelah simulasi dijalankan.)_
