# Cloud Infrastructure & High Availability Lab

Portfolio project yang mensimulasikan environment infrastruktur production-like menggunakan VMware Workstation, dibangun end-to-end sebagai persiapan melamar posisi **Cloud Infrastructure Engineer / DevOps Engineer / SRE**.

---

## 1. Project Overview

Project ini membangun infrastruktur 3-tier (web, application, database) yang lengkap dengan load balancing, high availability, monitoring, centralized logging, automation, security hardening, backup/disaster recovery, CI/CD, dan container orchestration — seluruhnya di atas 7 virtual machine yang saling terhubung, dijalankan di laptop pribadi dengan resource terbatas.

Yang membedakan project ini dari sekadar tutorial: **7 insiden nyata** ditemukan dan diperbaiki secara organik selama development (bukan simulasi terjadwal semata), masing-masing terdokumentasi lengkap dengan root cause analysis dan lessons learned di folder [`incidents/`](incidents/).

## 2. Business Problem

Tim infrastruktur kecil sering menghadapi tantangan: bagaimana membangun layanan yang tetap tersedia meski satu komponen gagal (High Availability), bagaimana mendeteksi masalah sebelum berdampak ke pengguna (Monitoring & Alerting), bagaimana memulihkan sistem dengan cepat saat terjadi kegagalan (Backup & DR), dan bagaimana melakukan semua ini secara konsisten dan berulang (Automation) — dengan resource dan anggaran terbatas. Project ini mensimulasikan penyelesaian masalah tersebut dari nol.

## 3. Project Objectives

- Membangun dan mengelola infrastruktur virtual dan cloud
- Mengimplementasikan High Availability dengan load balancing
- Menyiapkan monitoring, alerting, dan centralized logging
- Mengotomasi konfigurasi server dengan Ansible
- Menerapkan security hardening (firewall, SSH, least privilege)
- Menyiapkan backup terjadwal dan menguji disaster recovery secara nyata
- Membangun pipeline CI/CD
- Mendemonstrasikan container orchestration dasar (Kubernetes/K3s)
- Melakukan performance/load testing dan menyusun laporan
- Mendokumentasikan seluruh insiden nyata yang terjadi selama proses

## 4. Architecture

```
                         INTERNET / CLIENT
                                |
                                v
                     +----------------------+
                     |  lb-01 (HAProxy)     |
                     |  10.10.10.10         |
                     +----------+-----------+
                                |
                +---------------+---------------+
                |                               |
                v                               v
        +---------------+               +---------------+
        | web-01        |               | web-02        |
        | Nginx         |               | Nginx         |
        | 10.10.20.11   |               | 10.10.20.12   |
        +-------+-------+               +-------+-------+
                |                               |
                +---------------+---------------+
                                |
                                v
                     +----------------------+
                     | app-01 (FastAPI)     |
                     | 10.10.20.21          |
                     +----------+-----------+
                                |
                                v
                     +----------------------+
                     | db-01 (PostgreSQL)   |
                     | 10.10.20.31          |
                     +----------------------+

  Supporting services:
  - infra-01   : DNS + NAT Gateway + Ansible control node + Backup server (10.10.10.5)
  - monitor-01 : Prometheus + Grafana + Loki                              (10.10.20.41)
```

Topologi jaringan aktual (berbeda dari rencana awal karena keterbatasan VMware Workstation Player) didokumentasikan lengkap di [`docs/networking-updated.md`](docs/networking-updated.md), termasuk keputusan menjadikan `infra-01` sebagai NAT gateway multi-homed terpusat untuk seluruh segment Application.

## 5. Technology Stack

| Kategori | Teknologi |
|---|---|
| Virtualization | VMware Workstation Player |
| OS | Ubuntu Server 22.04 LTS |
| Load Balancer | HAProxy |
| Web Server | Nginx (reverse proxy) |
| Application | Python FastAPI + Uvicorn |
| Database | PostgreSQL 14 |
| DNS | BIND9 |
| Monitoring | Prometheus + Grafana + Node Exporter |
| Logging | Loki + Promtail |
| Automation | Ansible |
| Container Orchestration | K3s (Kubernetes) |
| CI/CD | GitHub Actions |
| Performance Testing | k6 |
| Security | UFW, SSH hardening |

## 6. Infrastructure & Virtualization

7 VM dibangun di atas VMware Workstation Player, masing-masing 1-2 vCPU dan 1-2GB RAM (disesuaikan dengan keterbatasan resource laptop):

| VM | Fungsi | IP |
|---|---|---|
| infra-01 | DNS, NAT Gateway, Ansible control node, Backup server | 10.10.10.5 / 10.10.20.5 |
| lb-01 | Load Balancer (HAProxy) | 10.10.10.10 / 10.10.20.10 |
| web-01, web-02 | Web Server + Reverse Proxy (Nginx) | 10.10.20.11, 10.10.20.12 |
| app-01 | Application Server (FastAPI) | 10.10.20.21 |
| db-01 | Database (PostgreSQL) | 10.10.20.31 |
| monitor-01 | Monitoring & Logging (Prometheus, Grafana, Loki) | 10.10.20.41 |

VM baru dibuat lewat proses **manual copy + cleanup identitas** (hostname, machine-id, SSH host key, MAC address) karena VMware Workstation Player tidak mendukung fitur Clone bawaan — proses ini didokumentasikan sebagai bagian dari pengalaman troubleshooting nyata sepanjang project.

## 7. Networking

- Static IP di semua VM, tidak ada DHCP untuk service.
- DNS internal (`lab.local`) lewat BIND9 di `infra-01`, dengan forward dan reverse zone.
- Segmentasi logical: Management (`10.10.10.0/24`) dan Application (`10.10.20.0/24`).
- `infra-01` berperan sebagai NAT gateway multi-homed, memberi akses internet ke seluruh VM di segment Application lewat IP forwarding + iptables MASQUERADE.

Detail lengkap dan perbandingan dengan rencana awal: [`docs/networking-updated.md`](docs/networking-updated.md).

## 8. High Availability

HAProxy melakukan health check (`GET /health`) ke `web-01` dan `web-02`, mendistribusikan traffic secara round-robin. Failover diuji dan diverifikasi: saat salah satu web server dimatikan, seluruh traffic otomatis dialihkan ke server yang masih hidup tanpa gangguan yang terlihat client, lalu kembali ke rotasi normal begitu server pulih. Didokumentasikan di [`incidents/incident-007-web-server-down.md`](incidents/incident-007-web-server-down.md).

## 9. Monitoring & Logging

**Monitoring**: Prometheus men-scrape metrics (CPU, Memory, Disk, service status) dari Node Exporter di semua VM. Dashboard Grafana "Infrastructure Overview" menampilkan status real-time. 4 alert rule aktif: Server Down, High CPU (>80%), High Memory (>80%), High Disk (>90%).

**Logging**: Loki mengumpulkan log dari Promtail yang berjalan di VM aplikasi, bisa di-query lewat Grafana Explore.

## 10. Automation (Ansible)

`infra-01` sebagai control node menjalankan playbook idempotent untuk instalasi Node Exporter dan security hardening ke seluruh VM. Struktur: `ansible/inventory/`, `ansible/roles/{node_exporter,security}/`, `ansible/playbooks/`. Idempotency dibuktikan berulang kali — task otomatis di-skip kalau kondisi sudah terpenuhi, tanpa efek samping ke konfigurasi yang sudah benar.

## 11. Security

UFW (default-deny) diterapkan di semua VM, SSH hardening (key-only, no root login), least privilege untuk service account dan database user. Detail lengkap termasuk 5 insiden firewall yang ditemukan dan diperbaiki: [`docs/SECURITY.md`](docs/SECURITY.md).

## 12. Backup & Disaster Recovery

Backup harian terjadwal (config dan database) dari `infra-01`, dengan rotation otomatis. Simulasi disaster recovery nyata dilakukan terhadap HAProxy config — **RTO aktual: 2 menit 42 detik**. Detail lengkap: [`docs/backup-recovery.md`](docs/backup-recovery.md).

## 13. CI/CD

GitHub Actions menjalankan pipeline otomatis setiap push: lint (flake8) → test import → build Docker image. Workflow: [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## 14. Container Orchestration (Kubernetes/K3s)

K3s single-node cluster di `infra-01`, mendemonstrasikan Deployment, Service, ConfigMap, horizontal scaling (2→4→2 pods), rolling update, dan rollback — termasuk insight nyata soal keterbatasan ConfigMap versioning dalam proses rollback Kubernetes.

## 15. Performance Testing

k6 dipakai untuk 3 skenario traffic (Normal 5 VU, High 50 VU, Burst 100 VU) terhadap endpoint lewat HAProxy. **Hasil kunci: 0% error rate di ketiga skenario**, termasuk saat lonjakan tiba-tiba ke 100 concurrent user. Laporan lengkap: [`performance/performance-report.md`](performance/performance-report.md).

## 16. Incident Management

7 insiden nyata ditemukan dan diselesaikan selama development (bukan simulasi semata), didokumentasikan lengkap dengan format Summary/Impact/Detection/Investigation/Root Cause/Resolution/Verification/Preventive Action/Lessons Learned di folder [`incidents/`](incidents/). Pola dominan: 5 dari 7 insiden berakar dari firewall default-deny yang diterapkan tanpa audit port lengkap — pelajaran yang dirumuskan menjadi prosedur standar untuk sisa project.

## 17. Lessons Learned

- **Firewall default-deny butuh audit port yang berkelanjutan**, bukan aktivitas satu kali — setiap service baru wajib diperiksa portnya sebelum firewall diterapkan.
- **VM yang berperan sebagai gateway/router butuh perlakuan khusus** — kesalahan konfigurasi di titik sentral (seperti `infra-01`) berdampak lebih luas dibanding end-host biasa.
- **Automation meningkatkan konsistensi dalam satu playbook, tapi tidak otomatis menjamin konsistensi antar playbook yang sengaja dipisah** — perbaikan di satu tempat perlu dicek dampaknya ke tempat lain yang serupa.
- **Health check yang "berhasil" secara teknis belum tentu benar** — status code harus dicocokkan dengan endpoint yang benar-benar merepresentasikan kesehatan aplikasi.
- Keterbatasan tooling (VMware Player vs Pro) memaksa adaptasi arsitektur (gateway terpusat vs VMnet per-segment) — trade-off ini didokumentasikan secara sadar, bukan disembunyikan.

## 18. Future Improvements

- [ ] Phase 10 — AWS (VPC, EC2, IAM, S3, CloudWatch) 
- [ ] Multi-node K3s cluster
- [ ] TLS/HTTPS untuk seluruh traffic web
- [ ] WAL archiving PostgreSQL untuk RPO database yang lebih ketat
- [ ] Backup ke remote storage (S3)
- [ ] IAM least-privilege policy untuk cloud

## 19. Repository Structure

```
cloud-infrastructure-lab/
├── ansible/           # Automation: inventory, roles, playbooks
├── application/       # FastAPI source code
├── backup/            # Backup scripts (config & database)
├── database/          # PostgreSQL access config
├── docker/            # Dockerfile
├── docs/              # Dokumentasi teknis (security, networking, backup, performance)
├── incidents/         # 7 laporan insiden nyata
├── kubernetes/        # K3s manifests
├── logging/           # Loki & Promtail config
├── monitoring/        # Prometheus config
├── performance/       # k6 load test scripts & report
└── .github/workflows/ # CI/CD pipeline
```

## 20. Author

Ariel J Sihombing — dibangun sebagai portfolio persiapan melamar posisi Cloud Infrastructure / DevOps / SRE Engineer.
