# MinIO Cluster Expansion Guide
## เพิ่ม Nodes ใหม่เข้า Cluster

---

## 📋 Overview

MinIO รองรับการขยายโดยการเพิ่ม **Server Pool** ใหม่

```
Before (4 nodes):
  Pool 1: minio{1...4}/data

After (8 nodes):
  Pool 1: minio{1...4}/data
  Pool 2: minio{5...8}/data    ← New pool
```

---

## ⚠️ Important Rules

1. **เพิ่มเป็น Pool ใหม่** - ไม่ใช่เพิ่ม node เข้า pool เดิม
2. **จำนวน nodes ใน pool ใหม่ต้อง ≥ 4**
3. **ต้อง Stop cluster ก่อนเพิ่ม**
4. **Config ต้องเหมือนกันทุก node**

---

## 🚀 Expansion Steps

### Step 1: Prepare New Nodes

ติดตั้ง OS และ mount disk บน nodes ใหม่ (5-8):

```bash
# บน node 5
sudo ./install.sh --node 5 --total 8 --ip 10.0.0.5

# บน node 6
sudo ./install.sh --node 6 --total 8 --ip 10.0.0.6

# บน node 7
sudo ./install.sh --node 7 --total 8 --ip 10.0.0.7

# บน node 8
sudo ./install.sh --node 8 --total 8 --ip 10.0.0.8
```

### Step 2: Update /etc/hosts (ทุก node เก่าและใหม่)

```bash
# เพิ่มบนทุก node (1-8)
cat >> /etc/hosts << 'EOF'
10.0.0.5 minio5
10.0.0.6 minio6
10.0.0.7 minio7
10.0.0.8 minio8
EOF
```

### Step 3: Generate New Config

```bash
# รันบน node 1
./add-node.sh --current 4 --new-start 5 --new-end 8
```

จะได้ไฟล์ `/etc/default/minio.new`:

```bash
MINIO_VOLUMES="http://minio{1...4}/data http://minio{5...8}/data"
```

### Step 4: Stop ALL Nodes

```bash
# รันบนทุก node (1-4)
sudo systemctl stop minio

# หรือจาก node 1:
for i in 1 2 3 4; do
    ssh minio${i} 'sudo systemctl stop minio'
done
```

### Step 5: Distribute New Config

```bash
# Copy config ไปทุก node (1-8)
for i in 1 2 3 4 5 6 7 8; do
    scp /etc/default/minio.new root@minio${i}:/etc/default/minio
done
```

### Step 6: Start ALL Nodes

```bash
# Start ทุก node พร้อมกัน
for i in 1 2 3 4 5 6 7 8; do
    ssh minio${i} 'sudo systemctl start minio' &
done
wait
```

### Step 7: Verify

```bash
mc admin info mycluster

# Should show 8 nodes:
#   Servers: 8
#   Drives: 8
```

---

## 📊 After Expansion

### Data Distribution

```
New objects → อาจไปอยู่ Pool 1 หรือ Pool 2
Old objects → ยังอยู่ Pool 1 (ไม่ย้ายอัตโนมัติ)
```

### Rebalance (Optional)

MinIO **ไม่** rebalance data อัตโนมัติ

ถ้าต้องการกระจาย data:
```bash
# Re-upload หรือ copy ไฟล์ใหม่
mc mirror mycluster/old-bucket mycluster/new-bucket
```

---

## 🔧 Update Cloudflare DNS

เพิ่ม A records สำหรับ nodes ใหม่:

```
minio.example.com    A    10.0.0.5    (Node 5)
minio.example.com    A    10.0.0.6    (Node 6)
minio.example.com    A    10.0.0.7    (Node 7)
minio.example.com    A    10.0.0.8    (Node 8)
```

---

## ⚠️ Rollback (ถ้าเกิดปัญหา)

```bash
# Stop all
for i in 1 2 3 4 5 6 7 8; do
    ssh minio${i} 'sudo systemctl stop minio' || true
done

# Restore old config on nodes 1-4
for i in 1 2 3 4; do
    ssh minio${i} 'cp /etc/default/minio.backup.* /etc/default/minio'
done

# Start only old nodes
for i in 1 2 3 4; do
    ssh minio${i} 'sudo systemctl start minio'
done
```

---

## 📋 Expansion Checklist

- [ ] New nodes installed with same OS
- [ ] Disks mounted at /mnt/minio-data
- [ ] minio-user created on new nodes
- [ ] /etc/hosts updated on ALL nodes
- [ ] Credentials match on ALL nodes
- [ ] Firewall allows 9000/9001
- [ ] Private network connectivity verified
- [ ] Backup current config
- [ ] Stop cluster
- [ ] Distribute new config
- [ ] Start all nodes
- [ ] Verify cluster health
- [ ] Update Cloudflare DNS
