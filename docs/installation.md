# MinIO Cloud Installation Guide

## 📋 Prerequisites

### Hardware Requirements (per node)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4GB | 8GB+ |
| Disk | 1+ disk (any size) | SSD/NVMe preferred |
| Network | 100Mbps | 1Gbps private network |

### Software Requirements

- Ubuntu 22.04/24.04 LTS หรือ Debian 12
- Root access
- Private network ระหว่าง nodes

---

## 🚀 Installation Steps

### Step 1: Prepare Servers

สร้าง VPS/Dedicated Servers อย่างน้อย 4 ตัว (ต่อ Pool)

```
Node 1: 10.0.0.3 (private IP)
Node 2: 10.0.0.5
Node 3: 10.0.0.4
Node 4: 10.0.0.2
```

### Step 2: Mount Data Disk (ถ้าใช้ Block Storage แยก)

```bash
# ตรวจสอบ disk
lsblk

# Format (ถ้าเป็น disk ใหม่)
sudo mkfs.xfs /dev/sdb

# สร้าง mount point
sudo mkdir -p /mnt/minio-data

# Mount
sudo mount /dev/sdb /mnt/minio-data

# Add to fstab (auto-mount on reboot)
echo '/dev/sdb /mnt/minio-data xfs defaults,noatime 0 2' | sudo tee -a /etc/fstab
```

### Step 3: Download Scripts

```bash
# บนทุก node
git clone https://github.com/vdohide-server/minio-cloud.git
cd minio-cloud
chmod +x *.sh scripts/*.sh
```

### Step 4: Configure pools.conf (บน node แรก)

```bash
# แก้ไข config/pools.conf - ใส่ IP จริงของแต่ละ node
nano config/pools.conf
```

```properties
# Credentials
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=YourVeryStrongPassword123!
MINIO_SITE_REGION=cloud

# Pool 1: Nodes 1-4
POOL1_START=1
POOL1_END=4
POOL1_DISKS=1
POOL1_PATH=/mnt/minio-data

NODE1_IP=10.0.0.3
NODE2_IP=10.0.0.5
NODE3_IP=10.0.0.4
NODE4_IP=10.0.0.2
```

### Step 5: Copy pools.conf to All Nodes

```bash
# จาก node 1, copy ไปทุก node
for ip in 10.0.0.5 10.0.0.4 10.0.0.2; do
    scp config/pools.conf root@${ip}:~/minio-cloud/config/
done
```

### Step 6: Run Installation (บนทุก node)

```bash
# Node 1
sudo ./install.sh --node 1 --ip 10.0.0.3

# Node 2 (SSH ไป node 2)
sudo ./install.sh --node 2 --ip 10.0.0.5

# Node 3
sudo ./install.sh --node 3 --ip 10.0.0.4

# Node 4
sudo ./install.sh --node 4 --ip 10.0.0.2
```

### Step 7: Start Cluster (ทุก node พร้อมกัน!)

```bash
# ใช้ update-nodes.sh จาก node 1:
./update-nodes.sh --start

# หรือรันบนทุก node:
sudo systemctl start minio
```

### Step 8: Verify Cluster

```bash
# ตรวจสอบ service
sudo systemctl status minio

# ดู logs
sudo journalctl -u minio -f

# Configure mc
mc alias set myminio http://localhost:9000 admin 'YourPassword!'

# Check cluster info
mc admin info myminio
```

---

## ✅ Post-Installation

### Create Bucket

```bash
mc mb myminio/videos
mc mb myminio/images

# Set public read (ถ้าต้องการ)
mc anonymous set download myminio/videos
```

### Test Upload/Download

```bash
# Upload
mc cp myfile.mp4 myminio/videos/

# Download
mc cp myminio/videos/myfile.mp4 ./

# List
mc ls myminio/videos/
```

---

## 📊 Monitoring

### Health Check

```bash
./scripts/health-check.sh
```

### Add to Cron

```bash
echo "*/5 * * * * /path/to/minio-cloud/scripts/health-check.sh >> /var/log/minio-health.log 2>&1" | crontab -
```

---

## 🔧 Common Commands

```bash
# Start/Stop/Restart ทุก node
./update-nodes.sh --start
./update-nodes.sh --stop
./update-nodes.sh --restart

# หรือบน node เดียว
sudo systemctl start minio
sudo systemctl stop minio
sudo systemctl restart minio

# View logs
sudo journalctl -u minio -f

# Cluster info
mc admin info myminio

# Heal (repair)
mc admin heal myminio --recursive
```

---

## 📈 Expanding Cluster

เมื่อต้องการเพิ่ม nodes ใหม่:

1. แก้ไข `config/pools.conf` - uncomment Pool 2
2. ติดตั้งบน nodes ใหม่
3. รัน `./update-nodes.sh --restart`

ดูรายละเอียดใน [Expansion Guide](expansion.md)

---

## ❓ Troubleshooting

### Cluster won't start

```bash
# Check logs
sudo journalctl -u minio -n 100

# Common issues:
# 1. Credentials don't match across nodes (check pools.conf)
# 2. /etc/hosts missing entries
# 3. Firewall blocking ports 9000/9001
# 4. Data directory permission issues
```

### Nodes can't connect

```bash
# Test connectivity
ping minio2

# Check firewall
sudo ufw status

# Open ports
sudo ufw allow 9000/tcp
sudo ufw allow 9001/tcp
```

### Permission denied

```bash
# Fix ownership
sudo chown -R minio-user:minio-user /mnt/minio-data
```
