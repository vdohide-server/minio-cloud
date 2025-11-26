# MinIO Multi-Drive Setup Guide

## Overview

สำหรับ nodes ที่มีหลาย disk (เช่น 4x 10TB HDD)

```
  Node 1          Node 2          Node 3          Node 4
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│ disk1   │    │ disk1   │    │ disk1   │    │ disk1   │
│ disk2   │    │ disk2   │    │ disk2   │    │ disk2   │
│ disk3   │    │ disk3   │    │ disk3   │    │ disk3   │
│ disk4   │    │ disk4   │    │ disk4   │    │ disk4   │
└─────────┘    └─────────┘    └─────────┘    └─────────┘
   40TB           40TB           40TB           40TB

Total: 160TB raw, ~73TB usable (EC:8)
```

---

## Step 1: Setup Drives

### 1.1 List Drives

```bash
lsblk
# Example output:
# sda     500G   ← OS disk
# sdb     10T    ← Data disk 1
# sdc     10T    ← Data disk 2
# sdd     10T    ← Data disk 3
# sde     10T    ← Data disk 4
```

### 1.2 Auto Setup Drives

```bash
# ใช้ script
sudo ./scripts/setup-drives.sh

# เลือก 1) Auto-detect drives
# Script จะ format และ mount ให้อัตโนมัติ
```

### 1.3 Manual Setup

```bash
# Format each drive
sudo mkfs.xfs /dev/sdb
sudo mkfs.xfs /dev/sdc
sudo mkfs.xfs /dev/sdd
sudo mkfs.xfs /dev/sde

# Create mount points
sudo mkdir -p /mnt/disk{1..4}

# Mount
sudo mount /dev/sdb /mnt/disk1
sudo mount /dev/sdc /mnt/disk2
sudo mount /dev/sdd /mnt/disk3
sudo mount /dev/sde /mnt/disk4

# Add to fstab
echo '/dev/sdb /mnt/disk1 xfs defaults,noatime 0 0' | sudo tee -a /etc/fstab
echo '/dev/sdc /mnt/disk2 xfs defaults,noatime 0 0' | sudo tee -a /etc/fstab
echo '/dev/sdd /mnt/disk3 xfs defaults,noatime 0 0' | sudo tee -a /etc/fstab
echo '/dev/sde /mnt/disk4 xfs defaults,noatime 0 0' | sudo tee -a /etc/fstab
```

---

## Step 2: Configure pools.conf

```properties
# Pool with multiple disks per node
POOL1_START=1
POOL1_END=4
POOL1_DISKS=4                    # ← 4 disks per node
POOL1_PATH=/mnt/disk             # ← Base path (will become /mnt/disk{1...4})

NODE1_IP=10.0.0.3
NODE2_IP=10.0.0.5
NODE3_IP=10.0.0.4
NODE4_IP=10.0.0.2
```

**Result MINIO_VOLUMES:**
```
http://minio{1...4}:9000/mnt/disk{1...4}
```

---

## Step 3: Install MinIO

```bash
# Node 1
sudo ./install.sh --node 1 --ip 10.0.0.3

# Node 2
sudo ./install.sh --node 2 --ip 10.0.0.5

# ... repeat for all nodes
```

---

## Step 4: Start Cluster

```bash
./update-nodes.sh --start

# Verify
mc admin info myminio
# Should show: 16 drives (4 nodes x 4 disks)
```

---

## Capacity Calculation

| Nodes | Disks/Node | Disk Size | Raw | EC | Usable |
|-------|------------|-----------|-----|-----|--------|
| 4 | 1 | 10TB | 40TB | 2 | ~20TB |
| 4 | 4 | 10TB | 160TB | 8 | ~73TB |
| 8 | 4 | 10TB | 320TB | 16 | ~146TB |
| 10 | 4 | 10TB | 400TB | 20 | ~182TB |

**Formula:** Usable ≈ Raw / 2.2 (with default EC)

---

## Mixed Disk Sizes (Different Pools)

```properties
# Pool 1: 4 nodes x 4 x 10TB = 160TB
POOL1_START=1
POOL1_END=4
POOL1_DISKS=4
POOL1_PATH=/mnt/disk

# Pool 2: 4 nodes x 4 x 16TB = 256TB (bigger disks!)
POOL2_START=5
POOL2_END=8
POOL2_DISKS=4
POOL2_PATH=/mnt/disk
```

MinIO จะกระจายไฟล์ใหม่ไป Pool ที่มีพื้นที่ว่างมากกว่า!

---

## Troubleshooting

### Drive Not Detected

```bash
# ตรวจสอบ drives
lsblk
fdisk -l

# Check if mounted
df -h /mnt/disk*
```

### Permission Issues

```bash
# Set ownership
sudo chown -R minio-user:minio-user /mnt/disk*
```

### Healing After Drive Replacement

```bash
# Check heal status
mc admin heal myminio --verbose

# Force heal
mc admin heal myminio --recursive
```
