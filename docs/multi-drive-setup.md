# MinIO Multi-Drive Setup Guide

## Overview

สำหรับ **Dedicated Servers** ที่มีหลาย disk ต่อเครื่อง (เช่น Hetzner Dedicated 4x 10TB)

```
  Server 1        Server 2        Server 3        Server 4
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│/mnt/disk1│    │/mnt/disk1│    │/mnt/disk1│    │/mnt/disk1│
│/mnt/disk2│    │/mnt/disk2│    │/mnt/disk2│    │/mnt/disk2│
│/mnt/disk3│    │/mnt/disk3│    │/mnt/disk3│    │/mnt/disk3│
│/mnt/disk4│    │/mnt/disk4│    │/mnt/disk4│    │/mnt/disk4│
└─────────┘    └─────────┘    └─────────┘    └─────────┘
   40TB           40TB           40TB           40TB

Total: 16 drives = 160TB raw → ~80TB usable (EC:8)
```

---

## Quick Start: 4 Servers x 4 Disks

### Step 1: Configure pools.conf

```properties
# config/pools.conf
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=YourSecurePassword123!

POOL1_START=1
POOL1_END=4
POOL1_DISKS=4
POOL1_PATH=/mnt/disk

NODE1_IP=10.0.0.1
NODE2_IP=10.0.0.2
NODE3_IP=10.0.0.3
NODE4_IP=10.0.0.4
```

### Step 2: Setup Disks (on each server)

```bash
# List disks
lsblk
# sda     500G   ← OS disk (NVMe)
# sdb     10T    ← Data disk 1
# sdc     10T    ← Data disk 2
# sdd     10T    ← Data disk 3
# sde     10T    ← Data disk 4

# Format all data disks
sudo mkfs.xfs -f /dev/sdb
sudo mkfs.xfs -f /dev/sdc
sudo mkfs.xfs -f /dev/sdd
sudo mkfs.xfs -f /dev/sde

# Create mount points
sudo mkdir -p /mnt/disk{1..4}

# Mount
sudo mount /dev/sdb /mnt/disk1
sudo mount /dev/sdc /mnt/disk2
sudo mount /dev/sdd /mnt/disk3
sudo mount /dev/sde /mnt/disk4

# Add to /etc/fstab
cat >> /etc/fstab << 'EOF'
/dev/sdb /mnt/disk1 xfs defaults,noatime 0 0
/dev/sdc /mnt/disk2 xfs defaults,noatime 0 0
/dev/sdd /mnt/disk3 xfs defaults,noatime 0 0
/dev/sde /mnt/disk4 xfs defaults,noatime 0 0
EOF
```

### Step 3: Install MinIO (on each server)

```bash
# Server 1
sudo ./install-multi-drive.sh --node 1 --ip 10.0.0.1

# Server 2
sudo ./install-multi-drive.sh --node 2 --ip 10.0.0.2

# Server 3
sudo ./install-multi-drive.sh --node 3 --ip 10.0.0.3

# Server 4
sudo ./install-multi-drive.sh --node 4 --ip 10.0.0.4
```

### Step 4: Start Cluster

```bash
# On all servers simultaneously
sudo systemctl start minio

# Verify
mc alias set myminio http://minio1:9000 admin 'YourSecurePassword123!'
mc admin info myminio
```

Expected output:
```
●  minio1:9000
   Uptime: 5 minutes
   Version: ...
   
   Total: 4 servers, 16 drives
   Online: 4 servers, 16 drives

   Storage: 160 TiB Used, 160 TiB Total
   Standard(EC:8): 8 parity shards
```

---

## Detailed Disk Setup

### Method 1: Using setup-drives.sh Script

```bash
# Use auto-detect (recommended)
sudo ./scripts/setup-drives.sh

# Select: 1) Auto-detect drives
# Script will format and mount automatically
```

### Method 2: Manual Setup

```bash
# 1. Check available drives
lsblk
fdisk -l

# 2. Format each drive with XFS (recommended)
sudo mkfs.xfs -f /dev/sdb
sudo mkfs.xfs -f /dev/sdc
sudo mkfs.xfs -f /dev/sdd
sudo mkfs.xfs -f /dev/sde

# 3. Create mount points
sudo mkdir -p /mnt/disk{1..4}

# 4. Mount drives
sudo mount /dev/sdb /mnt/disk1
sudo mount /dev/sdc /mnt/disk2
sudo mount /dev/sdd /mnt/disk3
sudo mount /dev/sde /mnt/disk4

# 5. Add to /etc/fstab for persistence
echo '/dev/sdb /mnt/disk1 xfs defaults,noatime 0 0' | sudo tee -a /etc/fstab
echo '/dev/sdc /mnt/disk2 xfs defaults,noatime 0 0' | sudo tee -a /etc/fstab
echo '/dev/sdd /mnt/disk3 xfs defaults,noatime 0 0' | sudo tee -a /etc/fstab
echo '/dev/sde /mnt/disk4 xfs defaults,noatime 0 0' | sudo tee -a /etc/fstab

# 6. Verify mounts
df -h /mnt/disk*
```

---

## pools.conf Configuration

```properties
# Credentials
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=!zX21042537

# Pool 1: 4 servers x 4 disks
POOL1_START=1
POOL1_END=4
POOL1_DISKS=4
POOL1_PATH=/mnt/disk

NODE1_IP=10.0.0.1
NODE2_IP=10.0.0.2
NODE3_IP=10.0.0.3
NODE4_IP=10.0.0.4
```

**Generated MINIO_VOLUMES:**
```
http://minio{1...4}:9000/mnt/disk{1...4}
```

This expands to:
- http://minio1:9000/mnt/disk1
- http://minio1:9000/mnt/disk2
- http://minio1:9000/mnt/disk3
- http://minio1:9000/mnt/disk4
- http://minio2:9000/mnt/disk1
- ... (16 drives total)

---

## Capacity Calculator

| Servers | Disks/Server | Disk Size | Total Drives | Raw | EC | Usable |
|---------|--------------|-----------|--------------|-----|-----|--------|
| 4 | 4 | 10TB | 16 | 160TB | EC:8 | ~80TB |
| 4 | 4 | 14TB | 16 | 224TB | EC:8 | ~112TB |
| 4 | 4 | 18TB | 16 | 288TB | EC:8 | ~144TB |
| 4 | 4 | 20TB | 16 | 320TB | EC:8 | ~160TB |
| 8 | 4 | 10TB | 32 | 320TB | EC:16 | ~160TB |

**Formula:** 
- Usable ≈ Raw / 2 (default erasure coding)
- EC parity = Total drives / 2

---

## Fault Tolerance

With **4 servers x 4 disks (16 drives)**, EC:8 gives you:

- **8 drives** can fail before data loss
- Up to **2 full servers** can go offline
- Automatic healing when drives come back online

---

## Hetzner Dedicated Server Recommendation

### AX102 (Best for price/performance)
- AMD Ryzen 9 5950X
- 128GB DDR4 RAM  
- 4x 10TB HDD (Enterprise or NAS grade)
- ~€150-180/month

### Network Setup
```bash
# Enable private network (vSwitch)
# Assign private IPs: 10.0.0.1, 10.0.0.2, etc.

# Edit /etc/network/interfaces
auto enp7s0
iface enp7s0 inet static
    address 10.0.0.1
    netmask 255.255.255.0
```

---

## Troubleshooting

### Drive Not Detected

```bash
# Check drives
lsblk
fdisk -l

# Check if mounted
df -h /mnt/disk*
mountpoint /mnt/disk1
```

### Permission Issues

```bash
# Set ownership
sudo chown -R minio-user:minio-user /mnt/disk*
```

### One Node Not Joining

```bash
# Check logs
journalctl -u minio -f

# Verify /etc/hosts
cat /etc/hosts | grep minio

# Test connectivity
ping minio1
ping minio2
```

### Healing After Drive Replacement

```bash
# Check heal status
mc admin heal myminio --verbose

# Force heal all buckets
mc admin heal myminio --recursive
```

---

## Expansion: Adding More Servers

To expand from 4 servers to 8 servers:

```properties
# Add Pool 2 in pools.conf
POOL2_START=5
POOL2_END=8
POOL2_DISKS=4
POOL2_PATH=/mnt/disk

NODE5_IP=10.0.0.5
NODE6_IP=10.0.0.6
NODE7_IP=10.0.0.7
NODE8_IP=10.0.0.8
```

Then run on new servers:
```bash
sudo ./install-multi-drive.sh --node 5 --ip 10.0.0.5
# ... etc
```
