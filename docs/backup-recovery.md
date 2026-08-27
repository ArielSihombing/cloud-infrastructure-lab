# Backup & Disaster Recovery

## 1. Ruang Lingkup

Dokumen ini mencakup strategi backup untuk **configuration files** kritis (Nginx, HAProxy) yang berjalan di `web-01`, `web-02`, dan `lb-01`. Backup database (`db-01`, PostgreSQL) akan ditambahkan pada sesi berikutnya setelah VM tersebut dinyalakan kembali.

## 2. Strategi Backup

**Lokasi backup server**: `infra-01` (berperan sebagai centralized backup point, konsisten dengan perannya sebagai gateway/DNS terpusat).

**Metode**: Dua script bash terpisah:
- `~/backups/backup-configs.sh` — menarik file konfigurasi lewat `scp` dari setiap VM target.
- `~/backups/backup-database.sh` — menjalankan `pg_dump` di `db-01` lewat SSH, hasil di-stream langsung ke `infra-01` tanpa menyisakan file sementara di server database.

Keduanya melakukan compress ke `.gz`/`.tar.gz` dan rotation otomatis (menghapus backup lebih dari 7 hari).

**Jadwal**: Cron job harian —
```
0 2 * * *  backup-configs.sh    (02:00)
30 2 * * * backup-database.sh   (02:30, diberi jeda agar tidak bersamaan)
```

**File yang di-backup**:
| VM | File | Path Asal |
|---|---|---|
| web-01 | Nginx config | `/etc/nginx/sites-available/default` |
| web-02 | Nginx config | `/etc/nginx/sites-available/default` |
| lb-01 | HAProxy config | `/etc/haproxy/haproxy.cfg` |
| db-01 | PostgreSQL dump (database `labapp`) | via `pg_dump`, bukan file statis |

## 3. RPO (Recovery Point Objective)

**RPO untuk configuration files: 24 jam.** **RPO untuk database: 24 jam** (dump harian jam 02:30) — untuk data transaksional yang lebih kritis di masa depan, RPO ini idealnya diperketat memakai PostgreSQL WAL archiving / continuous backup, tapi untuk lab environment saat ini, dump harian dianggap memadai karena `labapp` belum menyimpan data produksi nyata.

Karena backup dijalankan sekali sehari, skenario terburuk adalah kegagalan terjadi tepat sebelum jadwal backup berikutnya — dalam kasus ini, perubahan konfigurasi atau data yang dibuat dalam 24 jam terakhir berpotensi hilang dan perlu dikonfigurasi ulang manual.

Untuk lingkungan production sungguhan, RPO ini bisa diperketat (misalnya tiap 1 jam, atau memicu backup otomatis setiap kali file config berubah lewat git hook) — tapi untuk lab environment ini, 24 jam dianggap memadai karena perubahan config tidak sering terjadi di luar sesi kerja aktif.

## 4. RTO (Recovery Time Objective) — Target vs Aktual

**Target RTO: < 5 menit** untuk restore satu file configuration dan mengembalikan service ke kondisi normal.

### Simulasi Nyata — HAProxy Config Corruption

Pada 17 Agustus 2026, dilakukan simulasi disaster recovery dengan sengaja merusak `haproxy.cfg` di `lb-01` (menambahkan baris syntax tidak valid), lalu memulihkannya dari backup yang tersimpan di `infra-01`.

**Timeline:**
| Waktu (UTC) | Kejadian |
|---|---|
| 15:04:11 | Config dirusak, `systemctl restart haproxy` gagal (`Result: exit-code`) |
| 15:04:11 – 15:06:53 | Proses restore: extract backup di infra-01 → transfer via scp ke lb-01 → validasi syntax (`haproxy -c -f`) → restart service |
| 15:06:53 | HAProxy kembali `active (running)` |

**RTO Aktual: ± 2 menit 42 detik** — jauh di bawah target 5 menit.

### Langkah Restore yang Dilakukan
```bash
# Di infra-01: extract & kirim backup
cd ~/backups/configs
tar -xzf 20260817_145655.tar.gz
scp 20260817_145655/lb-01-haproxy.cfg ariel@10.10.10.10:/tmp/haproxy-restored.cfg

# Di lb-01: validasi & apply
sudo cp /tmp/haproxy-restored.cfg /etc/haproxy/haproxy.cfg
sudo haproxy -c -f /etc/haproxy/haproxy.cfg   # validasi syntax SEBELUM restart
sudo systemctl restart haproxy
```

**Poin penting**: validasi syntax (`haproxy -c -f`) dilakukan **sebelum** restart service — ini mencegah downtime berulang akibat config yang ternyata masih salah.

## 5. Temuan Tambahan Selama Simulasi

Simulasi restore ini secara tidak sengaja mengungkap **insiden kedua**: setelah HAProxy pulih, health check ke backend `web-01`/`web-02` tetap gagal (`Server ... is DOWN, reason: Layer4 timeout`), walau ping ICMP ke kedua host berhasil normal.

**Root cause**: Ansible role `security` (diterapkan di Phase 7) mengaktifkan UFW dengan default policy `deny`, tetapi rule eksplisit untuk port 80 (HTTP) belum ditambahkan — sehingga traffic HTTP, termasuk health check HAProxy, diblokir firewall di level OS meski service Nginx-nya sendiri berjalan normal.

**Resolution**: Task baru `Allow HTTP (Nginx/HAProxy)` ditambahkan ke role `security`, playbook dijalankan ulang (idempotent — hanya task baru ini yang `changed`, task lain tetap `ok` tanpa efek samping), dan port 80 berhasil dibuka di ketiga VM.

**Verification**: `curl http://<web-ip>/health` dari `lb-01` berubah dari gagal koneksi menjadi `502 Bad Gateway` — status ini sendiri sebenarnya *benar*, karena backend aplikasi (`app-01`) memang sedang tidak menyala saat pengujian, bukan lagi soal firewall.

**Lessons learned**: Saat menerapkan firewall dengan default-deny policy lewat automation, setiap service yang berjalan di server target harus diaudit portnya satu per satu sebelum rule diterapkan — celah ini lolos karena role `security` awalnya hanya mempertimbangkan port yang dipakai *Ansible sendiri* (SSH) dan *monitoring* (Node Exporter), lupa mempertimbangkan port aplikasi utama (HTTP/80) yang justru paling penting.

## 6. Insiden Tambahan Ditemukan Setelah Simulasi Restore

Proses memulihkan `lb-01` dari backup (bagian 5) menjadi titik awal yang secara tidak sengaja mengungkap dua insiden firewall tambahan saat security hardening diperluas ke `infra-01` dan `app-01`:

- **UFW forward policy di `infra-01`** memblokir NAT gateway untuk seluruh segment Application (detail lengkap di `docs/SECURITY.md`, Insiden 2).
- **Port 8000 (FastAPI) di `app-01`** belum diizinkan lintas segment, menyebabkan reverse proxy dari web tier gagal reach backend (detail di `docs/SECURITY.md`, Insiden 3).

Kedua insiden ini memperkuat pentingnya **audit port menyeluruh setiap kali firewall baru diterapkan** — bukan hanya untuk VM yang sedang dikonfigurasi, tapi juga dampaknya ke VM lain yang bergantung padanya (dalam kasus ini, `infra-01` sebagai gateway bersama).

## 7. Verifikasi Backup Database

Dump database `labapp` diverifikasi valid dengan cara membaca isi file terkompresi langsung (`zcat | head`) — struktur dump PostgreSQL standar (header versi, session settings, footer) semua muncul dengan benar, mengonfirmasi file tidak corrupt meski database saat ini belum menyimpan tabel data (baru dibuat di Phase 4, belum ada schema aplikasi).

```bash
zcat ~/backups/database/labapp_20260820_072630.sql.gz | head -30
```

Proses restore database (kalau dibutuhkan) akan mengikuti pola:
```bash
zcat labapp_<timestamp>.sql.gz | ssh ariel@10.10.20.31 "PGPASSWORD=ariel psql -h localhost -U labuser labapp"
```

## 8. Rencana Selanjutnya

- [x] Audit port UFW di semua VM aktif — selesai, temuan didokumentasikan di `docs/SECURITY.md`.
- [x] Backup database `db-01` (pg_dump terjadwal) — selesai, terverifikasi.
- [ ] Restore test khusus database (simulasi kegagalan PostgreSQL sungguhan, bukan cuma verifikasi isi dump).
- [ ] Backup ke remote storage (S3) sebagai opsi tambahan, sesuai rencana awal project (tertunda bersama Phase 10 — AWS, menunggu kartu pembayaran tersedia).
- [x] Terapkan Ansible role (Node Exporter + Security) ke `db-01` dan `monitor-01` — selesai.
