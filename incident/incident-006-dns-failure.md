# Incident 006 — DNS Failure (Simulation Runbook)

> **Status**: Runbook siap-eksekusi. Jalankan dari VM manapun selain `infra-01` (misalnya `web-01`), sambil `infra-01` tetap menyala.

## Summary
Simulasi kegagalan resolusi DNS internal (`lab.local`) dengan cara menghentikan BIND9 sementara di `infra-01`, menguji dampaknya ke VM lain yang bergantung pada DNS tersebut untuk resolve hostname internal maupun forwarding ke DNS publik.

## Simulation Steps

**1. Konfirmasi baseline dari VM klien (misal web-01):**
```bash
dig infra01.lab.local
dig app01.lab.local
ping -c 2 8.8.8.8
```

**2. Di infra-01, hentikan BIND9:**
```bash
sudo systemctl stop bind9
```

**3. Deteksi dari VM klien:**
```bash
dig infra01.lab.local
```
Harus muncul `SERVFAIL` atau timeout — bukan `NOERROR` seperti biasanya.

**4. Investigasi (di infra-01):**
```bash
sudo systemctl status bind9
sudo journalctl -u bind9 -n 30 --no-pager
sudo named-checkconf
```

**5. Resolusi:**
```bash
sudo systemctl start bind9
sudo systemctl status bind9
```

**6. Verifikasi (dari VM klien):**
```bash
dig infra01.lab.local
dig app01.lab.local
host db01.lab.local
```
Semua harus kembali `NOERROR` dengan jawaban IP yang benar.

## Troubleshooting Commands Tambahan (Sesuai Spesifikasi Awal Project)
```bash
dig <hostname>.lab.local
nslookup <hostname>.lab.local
host <hostname>.lab.local
ping <hostname>.lab.local
resolvectl status
```

## Expected Root Cause
Simulasi murni (service dihentikan manual) — representasi skenario nyata: BIND9 crash, konfigurasi zone file yang corrupt setelah edit manual, atau firewall yang tidak sengaja memblokir port 53 (skenario ini sudah pernah terjadi organik — lihat Incident 013, meski itu soal Node Exporter bukan DNS, polanya identik: audit port firewall yang tidak lengkap).

## Preventive Action (berlaku umum)
- Validasi config (`named-checkconf`, `named-checkzone`) sebelum restart BIND9 — pola yang sama seperti validasi HAProxy (`haproxy -c -f`) yang terbukti mencegah downtime berulang di Incident 010's resolution.
- DNS forwarder (`192.168.179.2`, NAT gateway VMware) sebagai fallback untuk domain publik — kegagalan BIND9 internal tidak semestinya memutus total akses internet VM, hanya resolusi hostname `.lab.local` yang terdampak.

## Actual Result
_(Isi setelah simulasi dijalankan.)_
