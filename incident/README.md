# Incident Log — Cloud Infrastructure & High Availability Lab

Seluruh incident di bawah ini **nyata**, ditemukan secara organik selama proses membangun infrastruktur (bukan simulasi terjadwal), kecuali Incident 007 yang memang dirancang sebagai demonstrasi terkontrol untuk membuktikan mekanisme High Availability.

## Ringkasan

| # | Judul | Severity | Kategori | Status |
|---|---|---|---|---|
| [007](incident-007-web-server-down.md) | Web Server Down (simulasi HA) | Low | Availability | ✅ Resolved |
| [008](incident-008-healthcheck-misconfiguration.md) | HAProxy Health Check Misconfiguration | High | Load Balancer | ✅ Resolved |
| [009](incident-009-firewall-port80-blocked.md) | Port 80 Terblokir UFW | High | Firewall | ✅ Resolved |
| [010](incident-010-ufw-forward-policy-nat-gateway.md) | UFW Forward Policy Memblokir NAT Gateway | Critical | Firewall / Gateway | ✅ Resolved |
| [011](incident-011-firewall-port8000-fastapi.md) | Port 8000 (FastAPI) Belum Diizinkan | High | Firewall | ✅ Resolved |
| [012](incident-012-firewall-port3100-loki.md) | Port 3100 (Loki) Belum Diizinkan | Medium | Firewall / Logging | ✅ Resolved |
| [013](incident-013-infra01-node-exporter-firewall.md) | Port 9100 di infra-01 Terlewat dari Playbook Terpisah | Medium | Firewall / Observability | ✅ Resolved |

## Pola yang Ditemukan

Lima dari tujuh insiden (009, 010, 011, 012, 013) berakar dari sebab yang berkaitan: **penerapan firewall default-deny (UFW) lewat Ansible tanpa audit port yang lengkap atau konsisten di setiap service/playbook**. Ini menjadi pelajaran paling berharga dari seluruh project — dirangkum di `docs/SECURITY.md`:

1. Setiap kali service baru ditambahkan ke VM manapun, port yang dipakainya harus segera diaudit dan ditambahkan ke role security terkait.
2. VM yang berperan sebagai router/gateway (bukan end-host biasa) butuh perhatian ekstra — kesalahan konfigurasi di titik sentral berdampak lebih luas (Incident 010).
3. Audit port bukan aktivitas satu kali di awal, melainkan proses berulang setiap kali VM yang sudah di-hardening menerima komponen baru (Incident 012 terjadi meski `monitor-01` sudah "aman" sebelumnya).
4. Teknik diagnosa cepat yang terbukti konsisten: bandingkan hasil `curl localhost` (lokal) vs `curl <ip-tujuan>` (lintas VM) — kalau lokal berhasil tapi lintas VM gagal/timeout, kecurigaan pertama selalu firewall, bukan aplikasi.
5. Automation meningkatkan konsistensi *dalam* satu playbook, tapi tidak otomatis menjamin konsistensi *antar* playbook yang sengaja dipisah (Incident 013) — perbaikan yang diterapkan ke satu role tidak serta-merta menjangkau playbook lain yang punya kebutuhan berbeda.

## Referensi Silang

- Detail konfigurasi firewall final dan tabel port lengkap: `docs/SECURITY.md`
- Detail backup, RPO/RTO, dan simulasi disaster recovery: `docs/backup-recovery.md`
- Perubahan arsitektur network dari rencana awal: `docs/networking-updated.md`
