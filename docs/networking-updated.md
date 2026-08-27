# Networking — Topologi Aktual (Update Pasca Phase 3)

> Dokumen ini menggantikan asumsi awal di perencanaan Phase 1 soal network segmentation menggunakan banyak VMnet custom dengan router terpisah. Topologi aktual yang terbukti berjalan di lab menggunakan **VMware Workstation Player** (bukan Pro), yang memiliki keterbatasan pada Virtual Network Editor.

## Perubahan Kunci dari Rencana Awal

| Aspek | Rencana Awal | Implementasi Aktual |
|---|---|---|
| Jumlah VMnet | 4 (satu per segment) | 2 (VMnet10 = Management, VMnet11 = Application) + NAT bawaan |
| Routing antar-segment | Diasumsikan router/L3 switch tersedia | `infra-01` berperan sebagai **multi-homed gateway** manual |
| Internet access | Tiap VM idealnya punya adapter NAT sendiri | Terpusat lewat **NAT gateway di infra-01** (IP forwarding + iptables MASQUERADE), semua VM lain cukup 1 default route |
| DNS | Single-homed di Management network | `infra-01` **multi-homed** untuk DNS (listen di `10.10.10.5` dan `10.10.20.5`), agar terjangkau dari kedua segment |

Alasan perubahan: VMware Workstation Player tidak mendukung pembuatan VMnet custom sebanyak dan sefleksibel Workstation Pro, dan tidak ada fitur untuk membuat "router VM" sederhana lewat GUI. Solusinya adalah menjadikan `infra-01` sebagai **jump host / gateway terpusat**, pola yang juga umum dipakai di infrastruktur nyata (bastion host, NAT gateway di cloud).

## Topologi Aktual

```
                         INTERNET
                             |
                    (VMware NAT / DHCP)
                             |
        +--------------------------------------------+
        |  infra-01 (multi-homed gateway)              |
        |  ens33: 10.10.10.5/24   (Management)          |
        |  ens37: DHCP            (NAT — internet)      |
        |  ens38: 10.10.20.5/24   (Application)         |
        |  - bind9 (DNS, listen di ens33 + ens38)        |
        |  - IP forwarding: ON                          |
        |  - iptables MASQUERADE: 10.10.20.0/24 -> ens37|
        +--------------------------------------------+
             |                              |
     VMnet10 (Management)           VMnet11 (Application)
     10.10.10.0/24                  10.10.20.0/24
             |                              |
    +-----------------+          +---------------------------+
    | lb-01            |         | web-01      web-02         |
    | ens33: 10.10.10.10 (Mgmt) |  10.10.20.11  10.10.20.12    |
    | ens37: DHCP (NAT)         |  (default route via         |
    | ens38: 10.10.20.10 (App)  |   10.10.20.5)                |
    | HAProxy -> web-01/web-02  |  Nginx                       |
    +-----------------+          +---------------------------+
```

## IP Address Plan (Aktual, Terverifikasi)

| Hostname | Interface | IP | Segment | Default Route | DNS |
|---|---|---|---|---|---|
| infra-01 | ens33 | 10.10.10.5/24 | Management | — (gateway itu sendiri) | self |
| infra-01 | ens37 | DHCP (≈192.168.179.x) | NAT | — | — |
| infra-01 | ens38 | 10.10.20.5/24 | Application | — | — |
| lb-01 | ens33 | 10.10.10.10/24 | Management | — | 10.10.10.5 |
| lb-01 | ens37 | DHCP (≈192.168.179.x) | NAT | — | — |
| lb-01 | ens38 | 10.10.20.10/24 | Application | — | — |
| web-01 | ens33 | 10.10.20.11/24 | Application | via 10.10.20.5 | 10.10.20.5 |
| web-02 | ens33 | 10.10.20.12/24 | Application | via 10.10.20.5 | 10.10.20.5 |

**Catatan penting**: `web-01` dan `web-02` sengaja dibuat **single-homed** (1 adapter saja) untuk menyederhanakan operasional — mereka tidak butuh akses langsung ke Management network, cukup lewat `infra-01` sebagai gateway untuk internet dan DNS. Ini konsisten dengan prinsip **least privilege** di security hardening (Phase 8 nanti).

## Komponen Kunci: NAT Gateway di infra-01

Konfigurasi yang membuat topologi ini berfungsi:

```bash
# IP forwarding (permanen, /etc/sysctl.conf)
net.ipv4.ip_forward=1

# NAT/masquerade untuk segment Application
sudo iptables -t nat -A POSTROUTING -s 10.10.20.0/24 -o ens37 -j MASQUERADE
sudo netfilter-persistent save
```

## Komponen Kunci: Multi-homed DNS di infra-01

```
# /etc/bind/named.conf.options
listen-on {
    127.0.0.1;
    10.10.10.5;
    10.10.20.5;
};
allow-query {
    127.0.0.1;
    10.10.10.0/24;
    10.10.20.0/24;
};
```


