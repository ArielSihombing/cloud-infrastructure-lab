# Incident 001 — Nginx Down (Simulation Runbook)

> **Status**: Runbook siap-eksekusi. Simulasi ini dirancang mengikuti format investigasi yang sama dengan insiden nyata (007-013), tapi belum dijalankan. Jalankan di `web-01`/`web-02`, lalu isi bagian "Actual Result" dengan output sesungguhnya.

## Summary
Simulasi kegagalan service Nginx di salah satu web server, untuk menguji deteksi monitoring dan proses recovery standar.

## Simulation Steps

**1. Konfirmasi baseline sebelum simulasi:**
```bash
curl -I http://10.10.10.10/health
sudo systemctl status nginx
```

**2. Hentikan Nginx secara sengaja:**
```bash
sudo systemctl stop nginx
```

**3. Deteksi lewat monitoring:**
- Dashboard HAProxy stats (`http://10.10.10.10:8404/stats`) — backend terkait harus berubah DOWN dalam beberapa detik.
- Grafana alert rule "Server Down" (kalau Node Exporter juga ikut terdampak) atau cek manual `curl -I http://10.10.20.11/health` langsung ke VM — harus connection refused.

**4. Investigasi:**
```bash
sudo systemctl status nginx
sudo journalctl -u nginx -n 30 --no-pager
sudo nginx -t
```

**5. Resolusi:**
```bash
sudo systemctl start nginx
sudo systemctl status nginx
```

**6. Verifikasi:**
```bash
curl -I http://10.10.10.10/health
```
Dashboard HAProxy stats harus kembali menunjukkan backend UP.

## Expected Root Cause
Service dihentikan manual (simulasi) — representasi skenario nyata: crash aplikasi, OOM kill, atau human error saat maintenance.

## Preventive Action (berlaku umum)
- `Restart=always` di systemd unit Nginx (default Ubuntu package sudah punya ini) memastikan auto-recovery untuk crash yang tidak disengaja.
- HAProxy health check (`/health`, hasil perbaikan Incident 008) memastikan traffic otomatis dialihkan ke backend lain selama downtime.

## Actual Result
_(Isi setelah simulasi dijalankan: timestamp kejadian, waktu deteksi, waktu resolusi, output command asli.)_
