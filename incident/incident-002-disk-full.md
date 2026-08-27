# Incident 002 — Disk Penuh (Simulation Runbook)

> **Status**: Runbook siap-eksekusi. Jalankan di VM manapun (disarankan `web-01` karena disk-nya paling kecil, 15GB), isi "Actual Result" setelah dijalankan.

## Summary
Simulasi disk penuh (>90%) untuk menguji deteksi alert Grafana ("High Disk Usage") dan proses cleanup standar.

## Simulation Steps

**1. Cek baseline disk usage:**
```bash
df -h /
```

**2. Buat file besar untuk memenuhi disk (sesuaikan ukuran dengan sisa ruang aktual, jangan sampai benar-benar 100% karena bisa mengunci sistem):**
```bash
fallocate -l 5G /tmp/dummy-fill-file
df -h /
```

**3. Deteksi lewat monitoring:**
- Grafana dashboard "Infrastructure Overview" — gauge Disk Usage untuk instance ini harus naik ke area merah (>90%).
- Alert rule "High Disk Usage" harus berubah status dari Normal → Pending → Firing.

**4. Investigasi — cari penyebab (dalam simulasi ini, cari file dummy tadi; di skenario nyata, ini langkah mencari penyebab sesungguhnya):**
```bash
du -sh /var/log/* 2>/dev/null | sort -rh | head -10
du -sh /tmp/* 2>/dev/null | sort -rh | head -10
```

**5. Resolusi — hapus file penyebab:**
```bash
rm -f /tmp/dummy-fill-file
df -h /
```

**6. Verifikasi:**
```bash
df -h /
```
Alert Grafana harus kembali ke status Normal dalam 1-2 menit (sesuai evaluation interval).

## Expected Root Cause
Simulasi murni (file dummy) — representasi skenario nyata: log yang tidak di-rotate, file upload yang menumpuk, atau core dump aplikasi.

## Preventive Action (berlaku umum)
- Rotation log sudah diterapkan di backup scripts (`find ... -mtime +7 -delete`), tapi belum ada rotation untuk log aplikasi/sistem umum — pertimbangkan `logrotate` untuk `/var/log` di semua VM.
- Alert "High Disk Usage" (threshold 90%) sudah dikonfigurasi sejak Phase 5, memberi peringatan dini sebelum disk benar-benar penuh dan mengganggu operasional (seperti insiden VMware disk-penuh yang terjadi di awal project, meski itu di level hypervisor host, bukan VM).

## Actual Result
_(Isi setelah simulasi dijalankan.)_
