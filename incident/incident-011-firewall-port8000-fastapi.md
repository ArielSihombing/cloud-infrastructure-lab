# Incident 011 — Port 8000 (FastAPI) Belum Diizinkan Lintas Segment

## Summary
Setelah role Ansible `security` diterapkan ke `app-01`, reverse proxy dari `web-01`/`web-02` ke `app-01:8000` gagal terhubung (timeout), meski FastAPI berjalan normal dan dapat diakses dari `localhost` milik `app-01` sendiri.

## Impact
- **Scope**: Seluruh request yang melewati web tier ke application tier terputus — client menerima `502 Bad Gateway` dari Nginx.
- **Severity**: High — memutus alur inti arsitektur 3-tier (`web → app`).

## Detection
```bash
ssh ariel@10.10.20.11 "curl -I http://10.10.20.21:8000/health"
```
dari `web-01` ke `app-01` menggantung tanpa response (harus dihentikan manual dengan Ctrl+C), sementara:
```bash
curl -I http://localhost:8000/health
```
dijalankan langsung di `app-01` berhasil normal (`405 Method Not Allowed` untuk HEAD request — status yang benar, endpoint sehat).

## Investigation
Pola perbedaan hasil (berhasil lokal, gagal lintas VM) langsung mengarahkan kecurigaan ke firewall, berdasarkan pengalaman Incident 009 (port 80) yang identik. Dicek:
```bash
sudo ufw status
```
di `app-01`, menunjukkan hanya port 22, 80, 9100 yang diizinkan — port 8000 tidak ada dalam daftar.

## Root Cause
Role `security` pada saat itu belum mempertimbangkan port aplikasi backend (8000), hanya mencakup port web-facing standar (80) dan port administratif/monitoring (22, 9100).

## Resolution
```yaml
- name: Allow FastAPI application port
  ufw:
    rule: allow
    port: '8000'
    proto: tcp
    src: 10.10.20.0/24
```
Task ditambahkan ke role `security`, dibatasi sumbernya ke segment internal (`10.10.20.0/24`) — bukan dibuka ke `Anywhere` seperti port 80, karena port aplikasi backend tidak perlu diakses langsung dari luar segment.

## Verification
```bash
ssh ariel@10.10.20.11 "curl http://10.10.20.21:8000/health"
```
berhasil mengembalikan response JSON lengkap dari FastAPI.

## Preventive Action
Ini insiden kedua dengan pola identik setelah Incident 009 — memperkuat kebutuhan proses standar "service baru → identifikasi port → tambahkan ke role security" sebagai bagian rutin, bukan reaktif.

## Lessons Learned
Membedakan gejala "gagal secara lokal" vs "gagal hanya lintas jaringan" adalah teknik diagnosa cepat yang efektif untuk mengisolasi masalah firewall dari masalah aplikasi — pola ini dipakai berulang kali sepanjang project (Incident 009, 011, 012) dan terbukti konsisten mempercepat root cause analysis.
