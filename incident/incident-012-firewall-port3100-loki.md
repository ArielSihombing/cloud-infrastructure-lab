# Incident 012 — Port 3100 (Loki) Belum Diizinkan Lintas Segment

## Summary
Setelah Loki diinstall di `monitor-01` (Phase 6 — Logging) dan Promtail dipasang di `app-01` untuk mengirim log sistem, Promtail gagal push data ke Loki selama lebih dari 10 menit meski kedua service berjalan sehat secara lokal masing-masing.

## Impact
- **Scope**: Tidak ada log yang berhasil terkirim dari `app-01` ke Loki — dashboard Grafana Explore menampilkan "No logs found" meski Promtail sudah aktif membaca file log sejak awal.
- **Severity**: Medium — tidak mengganggu layanan produksi (web/app/db tetap berfungsi normal), tapi menggagalkan seluruh fungsi observability logging yang baru dibangun.

## Detection
```bash
sudo journalctl -u promtail -n 30 --no-pager
```
di `app-01` menunjukkan error berulang:
```
error sending batch, will retry ... error="Post \"http://10.10.20.41:3100/loki/api/v1/push\": context deadline exceeded"
```
sejak Promtail pertama kali dijalankan, dengan interval retry yang semakin panjang (backoff), tapi tidak pernah berhasil.

## Investigation
```bash
curl -v http://10.10.20.41:3100/ready --connect-timeout 5
```
dari `app-01` ke `monitor-01` menghasilkan `Connection timed out` — bukan connection refused, mengindikasikan port diblokir firewall (bukan service Loki yang mati; service-nya sendiri terkonfirmasi `active` dan lokal `curl localhost:3100/ready` di `monitor-01` berhasil normal).

## Root Cause
Sama seperti Incident 009 dan 011: role `security` untuk `monitor-01` sudah mencakup port Grafana (3000) dan Prometheus (9090), tapi belum mencakup port Loki (3100) — karena Loki diinstall belakangan di Phase 6, setelah `monitor-01` sempat lebih dulu di-hardening di Phase 8.

## Resolution
```yaml
- name: Allow Loki (monitor-01 only)
  ufw:
    rule: allow
    port: '3100'
    proto: tcp
    src: 10.10.20.0/24
  when: inventory_hostname == 'monitor-01'
```
Task ditambahkan, playbook dijalankan ulang, Promtail di-restart di `app-01` untuk mempercepat retry cycle berikutnya (bukan menunggu backoff period habis secara alami).

## Verification
```bash
curl -v http://10.10.20.41:3100/ready --connect-timeout 5
```
berhasil `HTTP/1.1 200 OK`. Log test (`logger 'Test log entry...'`) berhasil muncul di Grafana Explore dalam hitungan detik setelah fix diterapkan, dengan total 62 baris log historis ikut terkirim sekaligus (backlog yang sempat tertahan sejak Promtail pertama kali start).

## Preventive Action
- Menegaskan kembali temuan dari `docs/SECURITY.md` bagian "Perbaikan Proaktif": audit port firewall bukan aktivitas satu kali di awal setup VM, melainkan proses yang harus diulang setiap kali komponen baru — termasuk tooling observability seperti Loki — ditambahkan ke VM yang sudah pernah di-hardening sebelumnya.

## Lessons Learned
Ini insiden keempat dengan pola firewall yang identik (setelah Incident 009, 010, 011), yang akhirnya menegaskan pola diagnostik yang konsisten dan cepat: begitu sebuah client menunjukkan error koneksi (bukan error aplikasi) ke service lain dalam segmen yang sama, langkah pertama adalah `curl` manual ke port target dari VM sumber untuk mengonfirmasi apakah masalahnya di level network/firewall sebelum menyelidiki lebih jauh ke konfigurasi aplikasi.
