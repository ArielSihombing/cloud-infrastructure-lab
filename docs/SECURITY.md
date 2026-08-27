# SECURITY.md — Cloud Infrastructure & High Availability Lab

## 1. Ringkasan

Dokumen ini merangkum seluruh langkah security hardening yang diterapkan di lab, metode penerapannya (manual vs automation), dan hasil audit port per VM. Semua hardening untuk `web-01`, `web-02`, `lb-01`, dan `infra-01` diterapkan lewat **Ansible** (Phase 7), memastikan konfigurasi konsisten dan dapat direplikasi (idempotent) ke VM baru kapan saja.

## 2. Linux Server Hardening

### 2.1 SSH
- **Key-based authentication** — semua VM menggunakan SSH key (ed25519), bukan password, sejak awal setup.
- **Password authentication dinonaktifkan** (`PasswordAuthentication no`) di `web-01`, `web-02`, `lb-01` lewat Ansible role `security`.
- **Root login dinonaktifkan** (`PermitRootLogin no`) — user harus login sebagai user biasa (`ariel`) lalu `sudo`, bukan langsung sebagai root.
- Setiap VM memiliki **SSH host key unik** (di-regenerate saat proses cloning VM untuk menghindari duplikasi identitas — lihat catatan operasional di bawah).

### 2.2 Least Privilege
- User aplikasi (`ariel`) bukan root, menggunakan `sudo` untuk task administratif.
- Passwordless sudo (`NOPASSWD`) diterapkan **khusus untuk kebutuhan automation Ansible**, bukan untuk login interaktif — trade-off yang disadari untuk kemudahan automation di lab, didokumentasikan secara eksplisit di sini.
- Database (`db-01`) menggunakan user aplikasi terbatas (`labuser`) dengan privilege hanya ke database `labapp`, bukan superuser `postgres` langsung.

### 2.3 Service Accounts
- `node_exporter` dan `prometheus` berjalan sebagai **system user tanpa home directory dan tanpa shell** (`--no-create-home --shell /bin/false`), meminimalkan permukaan serangan jika service tersebut dikompromikan.

## 3. Network & Firewall (UFW)

Setiap VM menjalankan **UFW dengan default-deny policy** — semua port tertutup kecuali yang eksplisit diizinkan.

| VM | Port Terbuka | Sumber (Source) | Keterangan |
|---|---|---|---|
| infra-01 | 22/tcp | Anywhere | SSH |
| infra-01 | 53/tcp, 53/udp | 10.10.10.0/24, 10.10.20.0/24 | DNS, dibatasi ke segment lab saja |
| lb-01 | 22/tcp | Anywhere | SSH |
| lb-01 | 80/tcp | Anywhere | HTTP (HAProxy frontend) |
| lb-01 | 9100/tcp | 10.10.20.0/24 | Node Exporter, hanya dari segment internal |
| lb-01 | 8404/tcp | *(tidak ada rule eksplisit — default deny berlaku)* | Dashboard stats HAProxy sengaja **tidak** dibuka ke luar |
| web-01 / web-02 | 22/tcp | Anywhere | SSH |
| web-01 / web-02 | 80/tcp | Anywhere | HTTP (Nginx) |
| web-01 / web-02 | 9100/tcp | 10.10.20.0/24 | Node Exporter, internal saja |
| app-01 | 8000/tcp | 10.10.20.0/24 | FastAPI application, dibatasi ke segment internal (ditambahkan setelah Insiden 3, lihat bagian 4) |
| db-01 | 5432/tcp | 10.10.20.0/24 | PostgreSQL, dibatasi ke segment Application — **tidak terbuka ke internet** |
| monitor-01 | 3000/tcp | Anywhere | Grafana web UI |
| monitor-01 | 9090/tcp | 10.10.20.0/24 | Prometheus, dibatasi ke segment internal |
| monitor-01 | 3100/tcp | 10.10.20.0/24 | Loki (log ingestion), menerima push dari Promtail di VM lain |
| infra-01 | 22/tcp | Anywhere | SSH |
| infra-01 | 9100/tcp | 10.10.20.0/24 | Node Exporter, ditambahkan belakangan (lihat Insiden 5) |
| infra-01 (gateway) | *(forward/NAT)* | — | `DEFAULT_FORWARD_POLICY=ACCEPT` — wajib untuk fungsi NAT gateway, lihat Insiden 2 |

**Prinsip yang diterapkan**: port administratif/monitoring (9100, 5432) dibatasi ke subnet internal; hanya port yang benar-benar perlu diakses publik (22 untuk admin, 80 untuk traffic user) yang dibuka luas.

## 4. Insiden Terkait Security (Selama Development)

### Insiden 1: Port 80 Terblokir Setelah Ansible Hardening
Saat pertama kali menerapkan role `security` lewat Ansible, port 80 (HTTP) tidak sengaja tidak dimasukkan ke dalam rule allow — mengakibatkan HAProxy health check gagal menjangkau backend Nginx meski service tersebut berjalan normal. Insiden ini terdeteksi lewat simulasi disaster recovery yang tidak berkaitan (restore HAProxy config), dan diperbaiki dengan menambahkan task eksplisit untuk port 80. Detail lengkap ada di `docs/backup-recovery.md`.

**Pelajaran**: default-deny firewall policy wajib disertai audit port per service — jangan hanya mempertimbangkan port yang dipakai tooling automation itu sendiri (SSH) dan monitoring (Node Exporter), tapi juga port aplikasi utama.

### Insiden 2: UFW Forward Policy Memblokir NAT Gateway (infra-01)
Saat UFW pertama kali diaktifkan di `infra-01` (yang berperan sebagai NAT gateway multi-homed untuk seluruh segment Application), default `DEFAULT_FORWARD_POLICY="DROP"` bawaan UFW ikut memblokir **semua traffic routed/forwarded** — termasuk masquerade NAT yang selama ini memberi akses internet ke `app-01`, `db-01`, `web-01`, `web-02`. Dampaknya lebih luas dari insiden port biasa: seluruh segment `10.10.20.0/24` kehilangan akses internet (`apt update` gagal, curl ke domain manapun timeout) begitu firewall diaktifkan.

**Deteksi**: ditemukan saat mencoba `apt install ufw` di `app-01` lewat Ansible — task gagal dengan pesan "Failed to update apt cache". Diagnosa awal sempat mengira masalah DNS/network dasar, tapi `ping` dan `dig` tetap berhasil normal — yang gagal spesifik hanya koneksi TCP keluar (port 80), mengarah ke kecurigaan firewall di level gateway, bukan di VM target itu sendiri.

**Fix**: ubah `DEFAULT_FORWARD_POLICY` dari `DROP` ke `ACCEPT` di `/etc/default/ufw`, lalu `ufw reload`.

**Pelajaran**: VM yang berperan sebagai router/gateway (bukan cuma end-host biasa) butuh perhatian khusus saat menerapkan firewall — policy default UFW dirancang untuk host biasa, bukan untuk node yang melakukan IP forwarding/NAT. Trade-off desain awal project (memakai `infra-01` sebagai gateway terpusat, dicatat di `docs/networking-updated.md`) ini kembali relevan di sini: sentralisasi gateway berarti satu kesalahan konfigurasi berdampak ke seluruh segment, bukan cuma satu VM.

### Insiden 3: Port 8000 (FastAPI) Belum Diizinkan Lintas Segment
Setelah role `security` diterapkan ke `app-01`, reverse proxy dari `web-01`/`web-02` ke `app-01:8000` gagal terhubung (timeout), meski `curl localhost:8000` dari `app-01` sendiri berhasil normal. Pola ini identik dengan Insiden 1 (port 80) — port aplikasi utama (kali ini port aplikasi backend, bukan web-facing) tidak masuk dalam rule allow awal karena role `security` pada mulanya hanya mempertimbangkan port administratif dan monitoring standar.

**Fix**: menambahkan task `Allow FastAPI application port` (8000/tcp, dibatasi ke `10.10.20.0/24`) ke role `security`, dijalankan ulang lewat playbook — idempotent, tidak mengganggu konfigurasi lain yang sudah benar.

### Insiden 4: Port 3100 (Loki) Belum Diizinkan Lintas Segment
Setelah Loki diinstall di `monitor-01` (Phase 6 — Logging) dan Promtail dipasang di `app-01` untuk mengirim log, Promtail gagal push data selama lebih dari 10 menit (`context deadline exceeded`, retry berulang) meski service Loki sendiri berjalan sehat secara lokal. Root cause identik dengan Insiden 3: port aplikasi baru (3100, log ingestion) belum ditambahkan ke role `security` untuk `monitor-01`.

**Deteksi**: dicurigai lewat pola yang sudah dikenali dari insiden-insiden sebelumnya — begitu Promtail menunjukkan error koneksi (bukan error aplikasi), langsung dicek `curl` manual ke port target dari VM sumber, yang mengonfirmasi `Connection timeout` murni network-level.

**Fix**: task `Allow Loki (monitor-01 only)` ditambahkan ke role `security` (3100/tcp, dibatasi `10.10.20.0/24`, kondisional `when: inventory_hostname == 'monitor-01'`), dijalankan ulang lewat playbook, Promtail di-restart untuk mempercepat retry cycle.

**Pelajaran**: pola dari Insiden 1, 3, dan 4 sekarang cukup jelas untuk dirumuskan sebagai **prosedur standar**: setiap kali komponen baru diinstall (baik itu aplikasi bisnis maupun tooling observability seperti Loki), langkah "tambahkan port ke role security" harus jadi bagian dari checklist instalasi itu sendiri — bukan langkah terpisah yang dikerjakan belakangan setelah troubleshooting.

### Insiden 5: Port 9100 (Node Exporter) di infra-01 Terlewat dari Playbook Khusus
Ditemukan beberapa hari setelah Insiden 4, saat memverifikasi dashboard Grafana "Infrastructure Overview" tidak menampilkan `infra-01` di panel Server Status maupun gauge CPU/Memory/Disk, meski Node Exporter di VM tersebut sudah `active (running)` sejak lama. Root cause: `infra-01` menggunakan playbook keamanan **terpisah** dari role `security` umum (`security-infra.yml`, dibuat khusus karena kebutuhan DNS dan forward policy — lihat Insiden 2), sehingga perbaikan port Node Exporter yang sudah diterapkan ke role `security` umum (untuk `web-01`, `web-02`, `app-01`, `db-01`, `monitor-01`) **tidak otomatis ikut** ke playbook terpisah ini.

**Deteksi**: `curl` dari `monitor-01` ke `infra-01:9100` menghasilkan `context deadline exceeded` (bukan "no route to host" seperti VM yang benar-benar mati) — pola yang sudah dikenali sebagai signature firewall blocking, bukan service down.

**Fix**: task `Allow Node Exporter port` ditambahkan ke `security-infra.yml`, dijalankan ulang.

**Pelajaran**: memisahkan playbook untuk kebutuhan khusus (seperti `infra-01` sebagai gateway) itu keputusan desain yang tepat, tapi punya konsekuensi tersembunyi — playbook yang terpisah **tidak mewarisi perbaikan** yang diterapkan ke role bersama. Saat sebuah rule ditambahkan karena insiden (seperti port 9100 di role `security` umum), perlu dicek juga apakah ada playbook terpisah lain yang butuh perbaikan setara.

## 5. Perbaikan Proaktif — db-01 dan monitor-01 (UFW Dasar Tanpa Insiden Susulan)

Setelah tiga insiden firewall berturut-turut (bagian 4), saat menerapkan role `security` dasar ke `db-01` dan `monitor-01` (SSH, HTTP, Node Exporter, FastAPI, plus PostgreSQL/Grafana/Prometheus yang sudah diketahui dipakai saat itu), kedua VM berhasil di-hardening pada percobaan pertama tanpa insiden konektivitas — memakai kondisi `when: inventory_hostname == '<host>'` agar rule tetap spesifik per VM.

Namun, pola ini **belum sepenuhnya antisipatif ke komponen yang baru ditambahkan belakangan**: Insiden 4 (Loki, bagian di atas) terjadi justru karena `monitor-01` sudah di-hardening lebih dulu, sebelum Loki diinstall di atasnya beberapa waktu kemudian di Phase 6. Ini bukan kegagalan pola, melainkan konfirmasi bahwa **audit port perlu diulang setiap kali service baru ditambahkan ke VM yang sudah di-hardening sebelumnya** — bukan cuma sekali di awal setup.

## 6. Keputusan Desain yang Disengaja (Trade-offs)

- **Domain internal `.local`** dipertahankan meski secara teknis reserved untuk mDNS (menimbulkan warning di `dig`) — mengubahnya ke `.internal` atau `home.arpa` akan memerlukan rebuild seluruh DNS zone yang sudah berfungsi; risiko downtime dianggap tidak sepadan untuk lab environment ini.
- **Flat network dengan gateway terpusat** (`infra-01` sebagai NAT gateway multi-homed) dipilih menggantikan rencana awal (VMnet terpisah per segment dengan router dedicated), karena keterbatasan VMware Workstation Player. Detail di `docs/networking-updated.md`.
- **Passwordless sudo untuk automation** — trade-off sadar demi kemudahan Ansible playbook berjalan tanpa interaksi manual; risiko dianggap dapat diterima karena akses SSH sendiri sudah dibatasi key-only dan lab tidak terekspos ke internet publik.

