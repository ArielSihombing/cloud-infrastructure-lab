# Incident 003 — CPU Tinggi (Simulation Runbook)

> **Status**: Runbook siap-eksekusi.

## Summary
Simulasi beban CPU tinggi (>80%) untuk menguji deteksi alert Grafana dan metodologi identifikasi proses penyebab.

## Simulation Steps

**1. Cek baseline CPU usage:**
```bash
top -bn1 | head -5
```

**2. Buat beban CPU tinggi (stress test sederhana pakai `yes` atau `dd`, atau install `stress`):**
```bash
sudo apt install -y stress
stress --cpu 2 --timeout 120s &
```

**3. Deteksi lewat monitoring:**
- Grafana gauge "CPU Usage (%)" untuk instance ini harus naik ke area merah.
- Alert rule "High CPU Usage" harus Firing dalam 1-2 menit.

**4. Investigasi — identifikasi proses penyebab:**
```bash
top -bn1 | head -15
ps aux --sort=-%cpu | head -10
```

**5. Resolusi — hentikan proses penyebab (dalam simulasi ini, `stress` akan berhenti otomatis setelah timeout, atau hentikan manual):**
```bash
pkill stress
```

**6. Verifikasi:**
```bash
top -bn1 | head -5
```
Alert harus kembali Normal.

## Expected Root Cause
Simulasi murni (`stress` tool) — representasi skenario nyata: infinite loop di kode aplikasi, cryptomining malware, atau query database yang tidak dioptimasi.

## Preventive Action (berlaku umum)
- Resource limit di level aplikasi (misalnya `systemd` `CPUQuota=`) bisa mencegah satu proses menghabiskan seluruh CPU VM.
- Untuk `app-01`/`db-01` yang memang butuh CPU untuk workload nyata, pertimbangkan vertical scaling (lihat rekomendasi di `performance/performance-report.md`) daripada membatasi resource secara ketat.

## Actual Result
_(Isi setelah simulasi dijalankan.)_
