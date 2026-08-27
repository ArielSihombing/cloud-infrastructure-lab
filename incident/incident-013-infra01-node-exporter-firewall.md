# Incident 013 — Port 9100 (Node Exporter) di infra-01 Terlewat dari Playbook Khusus

## Summary
Ditemukan saat verifikasi rutin dashboard Grafana "Infrastructure Overview": panel Server Status dan gauge CPU/Memory/Disk tidak pernah menampilkan `infra-01`, meski Node Exporter di VM tersebut sudah berjalan (`active`) sejak lama.

## Impact
- **Scope**: `infra-01` — VM paling kritis dalam arsitektur (DNS, NAT gateway, backup server, Ansible control node) — sama sekali tidak termonitor di Grafana.
- **Severity**: Medium — tidak mengganggu layanan produksi (DNS dan NAT tetap berfungsi normal), tapi menciptakan **blind spot** observability tepat di komponen paling sentral.

## Detection
Perbandingan visual dashboard: 6 dari 7 VM muncul normal di panel Server Status, `infra-01` (10.10.10.5) konsisten menunjukkan `0` meski VM tersebut sedang menyala.

## Investigation
```bash
sudo systemctl status node_exporter
```
di `infra-01` mengonfirmasi service `active (running)`. Namun:
```bash
curl -v http://10.10.10.5:9100/metrics --connect-timeout 5
```
dari `monitor-01` menghasilkan `context deadline exceeded` — pola signature firewall blocking yang sudah dikenali dari insiden-insiden sebelumnya (009, 010, 011, 012), bukan indikasi service mati.

Ditelusuri lebih lanjut: role Ansible `security` yang sudah diperbaiki sebelumnya (mencakup rule port 9100) hanya diterapkan ke `web-01`, `web-02`, `app-01`, `db-01`, `monitor-01`. `infra-01` menggunakan **playbook terpisah** (`security-infra.yml`), dibuat khusus sejak awal karena kebutuhan berbeda (DNS, forward policy untuk NAT gateway — lihat Incident 010) — playbook terpisah ini tidak pernah menerima rule port 9100.

## Root Cause
Pemisahan playbook keamanan untuk `infra-01` (keputusan desain yang tepat secara teknis, karena kebutuhannya memang berbeda dari VM lain) memiliki efek samping: perbaikan yang diterapkan ke role `security` bersama **tidak otomatis terwarisi** oleh playbook terpisah tersebut.

## Resolution
```yaml
- name: Allow Node Exporter port
  ufw:
    rule: allow
    port: '9100'
    proto: tcp
    src: 10.10.20.0/24
```
Task ditambahkan langsung ke `security-infra.yml`, dijalankan ulang.

## Verification
```bash
ssh ariel@10.10.20.41 "curl -s http://10.10.10.5:9100/metrics --connect-timeout 5 | head -3"
```
berhasil mengembalikan metrics. Dashboard Grafana "Infrastructure Overview" langsung menampilkan `infra-01` sebagai UP dan ikut muncul di seluruh gauge CPU/Memory/Disk setelah refresh.

## Preventive Action
- Saat menambahkan rule baru ke role `security` umum akibat insiden, secara eksplisit cek apakah ada playbook terpisah lain (saat ini hanya `security-infra.yml`) yang perlu perbaikan setara.
- Pertimbangkan me-refactor kedua playbook agar berbagi task dasar yang sama (misalnya lewat Ansible `include_tasks` untuk rule umum seperti SSH dan Node Exporter), dan hanya memisahkan task yang benar-benar spesifik (DNS, forward policy) — mengurangi risiko divergensi konfigurasi di masa depan.

## Lessons Learned
Ini insiden ketujuh dalam rangkaian masalah firewall yang serupa, tapi dengan akar penyebab yang sedikit berbeda dari yang lain — bukan lupa menambahkan port sama sekali, melainkan lupa bahwa perbaikan yang sudah dibuat tidak menjangkau semua tempat yang seharusnya. Ini pengingat penting: automation (Ansible) meningkatkan konsistensi *dalam* satu playbook, tapi tidak otomatis menjamin konsistensi *antar* playbook yang terpisah — duplikasi logika (bahkan yang disengaja karena alasan baik) tetap butuh proses sinkronisasi manual yang disiplin.
