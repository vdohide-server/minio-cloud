# MinIO Distributed Cluster - Cloud Deployment

โปรเจคนี้สำหรับติดตั้ง MinIO Distributed Cluster บน Cloud VPS/Dedicated Servers

---

## 📊 Architecture

```
                         ┌─────────────────┐
                         │   Cloudflare    │
                         │   (CDN + DNS)   │
                         └────────┬────────┘
                                  │
         ┌────────────────────────┼────────────────────────┐
         │                        │                        │
         ▼                        ▼                        ▼
   ┌──────────┐            ┌──────────┐            ┌──────────┐
   │  Node 1  │            │  Node 2  │            │  Node 3  │  ...
   │ 1-4 disk │◄──────────▶│ 1-4 disk │◄──────────▶│ 1-4 disk │
   │  :9000   │            │  :9000   │            │  :9000   │
   └──────────┘            └──────────┘            └──────────┘
        │                       │                       │
        └───────────────────────┴───────────────────────┘
                    Internal Network (Private)
```

---

## 🚀 Quick Start

### การติดตั้งใหม่

```bash
# 1. Clone repo
git clone <repo> && cd minio-cloud

# 2. แก้ไข config/pools.conf (ใส่ IP จริง)
nano config/pools.conf

# 3. ติดตั้งบนแต่ละ node
# Node 1
sudo ./install.sh --node 1 --ip 10.0.0.3

# Node 2, 3, 4...
sudo ./install.sh --node 2 --ip 10.0.0.5

# 4. Start cluster
./update-nodes.sh --start
```

### เพิ่ม Pool ใหม่

```bash
# 1. แก้ไข config/pools.conf (uncomment Pool 2)
nano config/pools.conf

# 2. ติดตั้งบน nodes ใหม่ (5-8)
sudo ./install.sh --node 5 --ip 10.0.0.8

# 3. อัพเดททุก node (เก่า + ใหม่)
./update-nodes.sh --dry-run    # ดูก่อน
./update-nodes.sh --restart    # รันจริง
```

---

## 📁 Files

```
minio-cloud/
├── config/
│   └── pools.conf           # ⭐ ไฟล์หลัก! กำหนด Pools + IPs
│
├── install.sh               # ติดตั้ง MinIO (1 disk/node)
├── install-multi-drive.sh   # ติดตั้ง MinIO (หลาย disk/node)
├── update-nodes.sh          # ⭐ อัพเดททุก node ตาม pools.conf
│
├── docs/
│   ├── installation.md      # คู่มือติดตั้ง
│   ├── expansion.md         # คู่มือเพิ่ม Pool
│   └── ...
│
└── scripts/
    ├── health-check.sh      # ตรวจสอบ cluster
    └── setup-drives.sh      # Format และ mount disks
```

---

## 🔧 Commands

| คำสั่ง | ใช้ทำอะไร |
|--------|----------|
| `./install.sh` | ติดตั้ง MinIO บน node ใหม่ |
| `./update-nodes.sh --dry-run` | ดูว่าจะอัพเดทอะไร |
| `./update-nodes.sh --restart` | อัพเดท config + restart ทุก node |
| `./update-nodes.sh --stop` | หยุด MinIO ทุก node |
| `./update-nodes.sh --start` | เริ่ม MinIO ทุก node |

---

## 📖 Documentation

- [Installation Guide](docs/installation.md)
- [Expansion Guide](docs/expansion.md) - เพิ่ม Pool ใหม่
- [Hetzner Setup](docs/hetzner-setup.md)
- [Multi-Drive Setup](docs/multi-drive-setup.md)

---

## ⚡ Requirements

| รายการ | ค่า |
|--------|-----|
| Nodes | 4+ (ต่อ Pool) |
| Disk/Node | 1-16 |
| RAM/Node | 4GB+ |
| Network | Private network ระหว่าง nodes |
| OS | Ubuntu 22.04/24.04, Debian 12 |
