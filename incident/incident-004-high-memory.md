# Incident 004 — Memory Tinggi (Simulation Runbook)

> **Status**: Runbook siap-eksekusi.

## Summary
Simulasi penggunaan memory tinggi (>80%) untuk menguji deteksi alert Grafana — insiden jenis ini sebenarnya sudah pernah terjadi secara **organik** (bukan simulasi) saat alert "High Memory Usage" sempat Firing secara nyata pada salah satu VM selama Phase 5, tapi tidak diselidiki lebih lanjut ke penyebab spesifiknya saat itu. Runbook ini melengkapi proses investigasi yang seharusnya dilakukan.

## Simulation Steps

**1. Cek baseline memory usage:**
```bash
free -h
```

**2. Buat beban memory tinggi:**
```bash
stress --vm 1 --vm-bytes 512M --timeout 120s &
```
(sesuaikan `--vm-bytes` dengan total RAM VM — misal untuk VM 1GB RAM, 512M sudah cukup signifikan)

**3. Deteksi lewat monitoring:**
- Grafana gauge "Memory Usage (%)" naik ke area merah.
- Alert rule "High Memory Usage" Firing.

**4. Investigasi — identifikasi proses penyebab:**
```bash
ps aux --sort=-%mem | head -10
free -h
```

**5. Resolusi:**
```bash
pkill stress
```

**6. Verifikasi:**
```bash
free -h
```

## Expected Root Cause
Simulasi murni — representasi skenario nyata: memory leak aplikasi (relevan untuk `app-01` yang menjalankan Uvicorn single-process jangka panjang), cache yang tidak dibatasi, atau terlalu banyak VM berjalan bersamaan di satu host fisik (kondisi yang berulang kali terjadi di laptop kamu sepanjang project ini).

## Preventive Action (berlaku umum)
- Resource limit (`memory: limits` di Kubernetes deployment — sudah diterapkan di Phase 12, `256Mi` limit untuk pod FastAPI) mencegah satu container menghabiskan memory node.
- Untuk VM biasa (bukan container), pertimbangkan systemd `MemoryMax=` pada service kritis.
- Insiden memory tinggi organik yang sempat terjadi di Phase 5 adalah pengingat nyata: menjalankan banyak VM bersamaan di satu laptop adalah sumber tekanan memory yang realistis, bukan cuma teori.

## Actual Result
_(Isi setelah simulasi dijalankan. Catatan: kejadian organik di Phase 5 — alert Firing terlihat di screenshot Alert Rules tanggal 17 Agustus 2026 — bisa dijadikan referensi tambahan, meski root cause spesifiknya tidak diselidiki mendalam saat itu.)_
