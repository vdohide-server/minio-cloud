# Hetzner Setup Guide for MinIO

## 📋 Overview

| Type | Hetzner Cloud | Hetzner Robot (Dedicated) |
|------|---------------|---------------------------|
| Console | console.hetzner.cloud | robot.hetzner.com |
| Private Network | Cloud Network (auto) | vSwitch (manual VLAN) |
| Pricing | Per hour | Per month |
| Best for | Testing, small scale | Production, large storage |

---

## Part 1: Hetzner Cloud (VPS)

### Step 1: Create Private Network

1. Login to [console.hetzner.cloud](https://console.hetzner.cloud)
2. ไปที่ **Networks** → **Create Network**

```
Name:      minio-network
IP Range:  10.0.0.0/16
```

3. **Add Subnet:**
```
Type:           Cloud
Network Zone:   eu-central
IP Range:       10.0.0.0/24
```

### Step 2: Create Servers

1. ไปที่ **Servers** → **Add Server**

```
Location:    Falkenstein (fsn1) หรือ Nuremberg (nbg1)
Image:       Ubuntu 24.04
Type:        CPX31 (4 vCPU, 8GB RAM) หรือใหญ่กว่า

Networking:
  ☑ Public IPv4
  ☑ Private Network: minio-network
      IP: 10.0.0.3 (กำหนดเอง)

SSH Keys:    เลือก SSH key ของคุณ
Name:        minio1
```

2. สร้าง 4 servers:

| Server | Private IP | Name |
|--------|------------|------|
| 1 | 10.0.0.3 | minio1 |
| 2 | 10.0.0.5 | minio2 |
| 3 | 10.0.0.4 | minio3 |
| 4 | 10.0.0.2 | minio4 |

### Step 3: Add Volume (Optional)

ถ้าต้องการ storage เพิ่ม:

1. **Volumes** → **Create Volume**
```
Name:       minio1-data
Size:       1000 GB
Automount:  ☑ (mount to /mnt/data)
Format:     xfs
Server:     minio1
```

### Step 4: Firewall

1. **Firewalls** → **Create Firewall**

```
Inbound Rules:
  SSH          TCP    22      Any (0.0.0.0/0)
  MinIO API    TCP    9000    Any (0.0.0.0/0)
  MinIO Console TCP   9001    Any (0.0.0.0/0)
  Internal     TCP    Any     10.0.0.0/24

Apply to: minio1, minio2, minio3, minio4
```

---

## Part 2: Hetzner Robot (Dedicated Servers)

### Step 1: Order Servers

ไปที่ [hetzner.com/sb](https://www.hetzner.com/sb) (Server Auction)

**Recommended Specs:**
```
AX41-NVMe:
  CPU:     AMD Ryzen 5 3600
  RAM:     64 GB DDR4
  Disk:    2 x 512GB NVMe
  Price:   ~€35-45/month
```

### Step 2: Create vSwitch

1. Login to [robot.hetzner.com](https://robot.hetzner.com)
2. ไปที่ **Servers** → เลือก Server → **vSwitch**
3. **Create vSwitch**

```
Name:      minio-vswitch
VLAN ID:   4000
```

4. **Add all servers** to vSwitch

### Step 3: Configure VLAN on Each Server

**Ubuntu 22.04/24.04 (Netplan):**

```bash
sudo nano /etc/netplan/99-vswitch.yaml
```

```yaml
network:
  version: 2
  vlans:
    vlan4000:
      id: 4000
      link: enp0s31f6    # ← ใช้ interface หลักของ server
      mtu: 1400
      addresses:
        - 10.0.0.3/24    # ← เปลี่ยนตาม node
```

```bash
sudo netplan apply
```

**IP Assignments:**

| Server | VLAN IP |
|--------|---------|
| 1 | 10.0.0.3/24 |
| 2 | 10.0.0.5/24 |
| 3 | 10.0.0.4/24 |
| 4 | 10.0.0.2/24 |

### Step 4: Test Connectivity

```bash
ping 10.0.0.5   # from node 1 to node 2
```

---

## Part 3: After Network Setup

### Update pools.conf

```properties
NODE1_IP=10.0.0.3
NODE2_IP=10.0.0.5
NODE3_IP=10.0.0.4
NODE4_IP=10.0.0.2
```

### Install MinIO

```bash
# On each node
git clone https://github.com/vdohide-server/minio-cloud.git
cd minio-cloud

# Edit config
nano config/pools.conf

# Install
sudo ./install.sh --node 1 --ip 10.0.0.3
```

---

## Network Diagram

```
                        ┌───────────────┐
                        │  Cloudflare   │
                        └───────┬───────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼ Public IP             ▼                       ▼
   ┌─────────────┐        ┌─────────────┐        ┌─────────────┐
   │   minio1    │        │   minio2    │        │   minio3    │
   │ 65.21.x.x   │        │ 65.21.x.x   │        │ 65.21.x.x   │
   ├─────────────┤        ├─────────────┤        ├─────────────┤
   │  10.0.0.3   │◄──────▶│  10.0.0.5   │◄──────▶│  10.0.0.4   │
   └─────────────┘        └─────────────┘        └─────────────┘
         │                      │                      │
         └──────────────────────┴──────────────────────┘
                    Private Network / vSwitch
```

---

## Checklist

### Hetzner Cloud
- [ ] Created Private Network
- [ ] Created 4 Servers in same location
- [ ] Assigned Private IPs
- [ ] Configured Firewall
- [ ] Tested ping between nodes

### Hetzner Robot
- [ ] Ordered servers
- [ ] Created vSwitch
- [ ] Configured VLAN interface on each server
- [ ] Tested ping between nodes
