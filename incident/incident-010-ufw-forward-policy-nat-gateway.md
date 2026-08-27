# Incident 010 — UFW Forward Policy Memblokir NAT Gateway di infra-01

## Summary
Saat UFW pertama kali diaktifkan di `infra-01` (yang berperan sebagai NAT gateway multi-homed untuk segment Application), default `DEFAULT_FORWARD_POLICY="DROP"` bawaan UFW ikut memblokir seluruh traffic routed/forwarded — termasuk NAT masquerade yang menjadi satu-satunya jalur internet bagi `app-01`, `db-01`, `web-01`, dan `web-02`. Ini insiden dengan dampak paling luas di antara seluruh insiden yang ditemukan selama project.

## Impact
- **Scope**: Seluruh VM di segment `10.10.20.0/24` kehilangan akses internet secara bersamaan (bukan cuma satu service atau satu VM).
- **Severity**: Critical — memutus kemampuan `apt update`, `apt install`, dan semua komunikasi keluar dari segment Application, termasuk yang dibutuhkan Ansible untuk instalasi package.

## Detection
Saat menjalankan Ansible playbook `security` ke `app-01`, task `apt install ufw` gagal dengan pesan "Failed to update apt cache: unknown reason". Diagnosa awal sempat mengarah ke masalah DNS/network dasar, tapi `ping 8.8.8.8` dan `dig` tetap berhasil normal dari `app-01` — yang gagal spesifik hanya koneksi TCP keluar (`curl` ke domain manapun, termasuk `example.com`, timeout).

## Investigation
```bash
sudo ufw status verbose
```
di `infra-01` menunjukkan baris kunci:
```
Default: deny (incoming), allow (outgoing), deny (routed)
```
"deny (routed)" adalah indikasi bahwa semua traffic yang melewati `infra-01` sebagai router/gateway (bukan traffic yang ditujukan ke `infra-01` sendiri) diblokir.

```bash
cat /etc/default/ufw | grep FORWARD
```
mengonfirmasi `DEFAULT_FORWARD_POLICY="DROP"` — nilai default UFW yang tidak sesuai untuk node yang berfungsi sebagai NAT gateway.

## Root Cause
UFW secara default dirancang untuk host biasa (bukan router), sehingga `DEFAULT_FORWARD_POLICY` bawaannya `DROP`. Saat diaktifkan tanpa penyesuaian, policy ini bertentangan langsung dengan konfigurasi `iptables -t nat -A POSTROUTING ... -j MASQUERADE` yang sudah dipasang manual sejak Phase 3 sebagai fondasi gateway internet untuk seluruh segment Application.

## Resolution
```bash
sudo sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
sudo ufw reload
```

## Verification
```bash
sudo ufw status verbose
```
baris "Default" berubah menjadi `deny (incoming), allow (outgoing), allow (routed)`. Dari `app-01`:
```bash
curl -I http://example.com --connect-timeout 10
```
berhasil mengembalikan `HTTP/1.1 200 OK` — akses internet pulih sepenuhnya untuk seluruh segment.

## Preventive Action
- VM yang berperan sebagai router/gateway (bukan end-host biasa) harus diberi perhatian khusus terpisah saat menerapkan firewall — checklist security untuk node semacam ini wajib mencakup pengecekan `DEFAULT_FORWARD_POLICY`, bukan hanya rule inbound/outbound biasa.
- Playbook Ansible untuk `infra-01` dipisahkan dari role `security` umum (`security-infra.yml`), memberi ruang untuk task khusus gateway seperti ini di masa depan.

## Lessons Learned
Ini konsekuensi langsung dari keputusan desain awal untuk memakai gateway terpusat (`infra-01` multi-homed) menggantikan router per-segment yang direncanakan semula (lihat `docs/networking-updated.md`). Trade-off sentralisasi berarti kesalahan konfigurasi di satu titik berdampak ke banyak VM sekaligus — bukan alasan untuk menghindari pola ini (masih representatif untuk NAT Gateway di cloud sungguhan), tapi alasan kuat untuk menguji perubahan firewall di titik sentral seperti ini dengan lebih hati-hati dibanding di end-host biasa.
