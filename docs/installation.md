# MinIO Cloud Installation Guide
## Complete Step-by-Step

---

## 📋 Prerequisites

### Hardware Requirements (per node)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4GB | 8GB+ |
| Disk | 1 disk (any size) | SSD preferred |
| Network | 100Mbps | 1Gbps |

### Software Requirements

- Ubuntu 22.04/24.04 LTS หรือ Debian 12
- Root access
- Private network ระหว่าง nodes

---

## 🚀 Installation Steps

### Step 1: Prepare Servers

สร้าง VPS/Dedicated Servers 4 ตัว (หรือมากกว่า เป็นเลขคู่)

```
Node 1: 10.0.0.1 (private IP)
Node 2: 10.0.0.2
Node 3: 10.0.0.3
Node 4: 10.0.0.4
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

### Step 3: Download Installation Scripts

```bash
# บนทุก node
git clone https://github.com/your-repo/minio-cloud.git
cd minio-cloud
chmod +x *.sh scripts/*.sh
```

### Step 4: Configure Node IPs

```bash
# แก้ไขไฟล์ config/nodes.txt
nano config/nodes.txt

# ใส่ IP จริงของแต่ละ node:
minio1=10.0.0.1
minio2=10.0.0.2
minio3=10.0.0.3
minio4=10.0.0.4
```

### Step 5: Set Credentials

```bash
# Copy template
cp config/minio.env.template config/minio.env

# แก้ไข credentials
nano config/minio.env

# เปลี่ยน password ให้ strong!
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=YourVeryStrongPassword123!
```

### Step 6: Run Installation (บนทุก node)

```bash
# Node 1
sudo ./install.sh --node 1 --total 4 --ip 10.0.0.1

# Node 2 (SSH ไป node 2)
sudo ./install.sh --node 2 --total 4 --ip 10.0.0.2

# Node 3
sudo ./install.sh --node 3 --total 4 --ip 10.0.0.3

# Node 4
sudo ./install.sh --node 4 --total 4 --ip 10.0.0.4
```

### Step 7: Copy Config to All Nodes

```bash
# จาก node 1, copy config ไปทุก node
for i in 2 3 4; do
    scp config/minio.env minio${i}:~/minio-cloud/config/
    scp /etc/default/minio root@minio${i}:/etc/default/minio
done
```

### Step 8: Update /etc/hosts on All Nodes

```bash
# บนทุก node, เพิ่ม:
cat >> /etc/hosts << 'EOF'
10.0.0.1 minio1
10.0.0.2 minio2
10.0.0.3 minio3
10.0.0.4 minio4
EOF
```

### Step 9: Start Cluster (ทุก node พร้อมกัน!)

```bash
# รันบนทุก node
sudo systemctl start minio

# หรือใช้ script รันจาก node 1:
for i in 1 2 3 4; do
    ssh minio${i} 'sudo systemctl start minio' &
done
wait
```

### Step 10: Verify Cluster

```bash
# ตรวจสอบ service
sudo systemctl status minio

# ดู logs
sudo journalctl -u minio -f

# Configure mc
mc alias set mycluster http://localhost:9000 admin YourPassword

# Check cluster info
mc admin info mycluster
```

---

## ✅ Post-Installation

### Create Bucket

```bash
mc mb mycluster/videos
mc mb mycluster/images

# Set public read (ถ้าต้องการ)
mc anonymous set download mycluster/videos
```

### Test Upload/Download

```bash
# Upload
mc cp myfile.mp4 mycluster/videos/

# Download
mc cp mycluster/videos/myfile.mp4 ./

# List
mc ls mycluster/videos/
```

---

## 🌐 Configure Cloudflare

ดูรายละเอียดใน:
- [cloudflare/setup-dns.md](../cloudflare/setup-dns.md)
- [cloudflare/cache-rules.md](../cloudflare/cache-rules.md)

---

## 📊 Monitoring

### Manual Health Check

```bash
./scripts/health-check.sh
```

### Add to Cron

```bash
# Check every 5 minutes
echo "*/5 * * * * /path/to/minio-cloud/scripts/health-check.sh >> /var/log/minio-health.log 2>&1" | crontab -
```

---

## 🔧 Common Commands

```bash
# Start/Stop/Restart
sudo systemctl start minio
sudo systemctl stop minio
sudo systemctl restart minio

# View logs
sudo journalctl -u minio -f

# Cluster info
mc admin info mycluster

# Disk usage
mc admin info mycluster --json | jq '.usage'

# Heal (repair)
mc admin heal mycluster --recursive
```

---

## ❓ Troubleshooting

### Cluster won't start

```bash
# Check logs
sudo journalctl -u minio -n 100

# Common issues:
# 1. Credentials don't match across nodes
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
