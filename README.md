# MinIO Distributed Cluster - Cloud Deployment
## 4+ Nodes x 1 Disk per Node (No Docker)

โปรเจคนี้สำหรับติดตั้ง MinIO Distributed Cluster บน Cloud VPS/Dedicated Servers
โดยแต่ละ node มี disk เดียว

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
   │  1 disk  │◄──────────▶│  1 disk  │◄──────────▶│  1 disk  │
   │  :9000   │            │  :9000   │            │  :9000   │
   └──────────┘            └──────────┘            └──────────┘
        │                       │                       │
        └───────────────────────┴───────────────────────┘
                    Internal Network (Private)
```

---

## 📁 Files

```
minio-cloud/
├── README.md                    # This file
├── install.sh                   # Main installation script
├── add-node.sh                  # Add new node to cluster
├── config/
│   ├── minio.env.template       # Environment template
│   └── minio.service            # Systemd service
├── cloudflare/
│   ├── setup-dns.md             # DNS configuration guide
│   └── cache-rules.md           # Cache rules for HLS
└── scripts/
    ├── health-check.sh          # Health monitoring
    └── backup-config.sh         # Backup cluster config
```

---

## 🚀 Quick Start

### Step 1: Clone และ Configure

```bash
# บน node แรก
git clone <repo> && cd minio-cloud

# แก้ไข config
cp config/minio.env.template config/minio.env
nano config/minio.env
```

### Step 2: ติดตั้ง (รันบนทุก node)

```bash
# Node 1
sudo ./install.sh --node 1 --total 4 --ip 10.0.0.1

# Node 2
sudo ./install.sh --node 2 --total 4 --ip 10.0.0.2

# ... และต่อไป
```

### Step 3: Start Cluster

```bash
# รันบนทุก node พร้อมกัน
sudo systemctl start minio
```

---

## 📖 Documentation

- [Installation Guide](docs/installation.md)
- [Hetzner Setup (Cloud & Robot)](docs/hetzner-setup.md)
- [Cloudflare Setup](cloudflare/setup-dns.md)
- [Expanding Cluster](docs/expansion.md)

---

## ⚡ Minimum Requirements

| Requirement | Value |
|-------------|-------|
| Nodes | 4+ (ต้องเป็นเลขคู่) |
| Disk/Node | 1+ |
| RAM/Node | 4GB+ |
| Network | Private network ระหว่าง nodes |
| OS | Ubuntu 22.04/24.04, Debian 12 |
