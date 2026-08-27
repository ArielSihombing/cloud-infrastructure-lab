# Incident 009 — Port 80 Terblokir Setelah Ansible Security Hardening

## Summary
Setelah role Ansible `security` diterapkan ke `web-01`, `web-02`, dan `lb-01` (mengaktifkan UFW dengan default-deny policy), HAProxy health check kembali gagal — kali ini bukan karena path yang salah (lihat Incident 008), melainkan port 80 (HTTP) belum termasuk dalam rule allow UFW.

## Impact
- **Scope**: Seluruh backend web (`web-01`, `web-02`) tidak dapat dijangkau lewat HTTP dari luar VM masing-masing, termasuk oleh HAProxy.
- **Severity**: High — ditemukan saat simulasi disaster recovery HAProxy config (insiden terpisah), menunjukkan bahwa masalah ini sudah aktif sebelum disadari.

## Detection
Setelah restore config HAProxy dari backup (bagian dari simulasi disaster recovery Phase 9), dashboard stats HAProxy tetap menunjukkan backend DOWN dengan alasan `Layer4 timeout` — berbeda dari Incident 008 (`L7STS/404`), mengindikasikan koneksi TCP-nya sendiri yang gagal, bukan soal response HTTP.

## Investigation
```bash
ping -c 2 10.10.20.11    # berhasil normal
sudo ufw status           # di web-01
```
`ping` (ICMP) berhasil normal, tapi `ufw status` menunjukkan rule hanya untuk port `22` (SSH) dan `9100` (Node Exporter) — **port 80 tidak ada dalam daftar allow**.

## Root Cause
Role Ansible `security` (Phase 7) dirancang dengan default-deny UFW policy, tapi rule eksplisit untuk port 80 (HTTP, dipakai Nginx) tidak dimasukkan saat role pertama kali ditulis — hanya port administratif (SSH) dan monitoring (Node Exporter) yang dipertimbangkan.

## Resolution
Task baru ditambahkan ke role `security`:
```yaml
- name: Allow HTTP (Nginx/HAProxy)
  ufw:
    rule: allow
    port: '80'
    proto: tcp
```
Playbook dijalankan ulang (`ansible-playbook site.yml --limit web-01,web-02,lb-01`) — idempotent, hanya task baru ini yang berstatus `changed`, task lain tetap `ok` tanpa efek samping.

## Verification
```bash
ssh ariel@10.10.20.11 "sudo ufw status"
```
menunjukkan `80/tcp ALLOW Anywhere`. `curl -I http://10.10.20.11/health` dari `lb-01` berubah dari gagal koneksi menjadi response valid (walau sempat `502 Bad Gateway` karena `app-01` sedang mati saat itu — status tersebut sendiri sudah benar, bukan lagi soal firewall).

## Preventive Action
- Setiap kali service baru menerima traffic dari VM lain, port-nya wajib diaudit dan ditambahkan ke role security sebagai bagian dari proses "menambahkan service", bukan langkah terpisah setelah insiden.
- Pola ini terulang di Incident 011 (port 8000) dan Incident 012 (port 3100) — akhirnya dirumuskan sebagai prosedur standar (lihat `docs/SECURITY.md`, bagian "Perbaikan Proaktif").

## Lessons Learned
Default-deny firewall policy adalah praktik yang benar secara prinsip, tapi implementasinya rawan lubang kalau tidak disertai daftar port yang benar-benar lengkap sejak awal. Insiden ini juga menunjukkan nilai dari idempotency Ansible: perbaikan bisa diterapkan ulang dengan aman tanpa mengganggu konfigurasi lain yang sudah benar.
