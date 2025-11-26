# MinIO Cluster Expansion Guide

## 📋 Overview

MinIO รองรับการขยายโดยการเพิ่ม **Server Pool** ใหม่ได้ไม่จำกัด

```
Pool 1: minio{1...4}:9000/mnt/minio-data     (เริ่มต้น)
Pool 2: minio{5...8}:9000/mnt/minio-data     (เพิ่มครั้งที่ 1)
Pool 3: minio{9...12}:9000/data/disk{1...4}  (เพิ่มครั้งที่ 2)
...                                           (ไม่จำกัด!)
```

### รองรับ Disk Size ต่างกันได้

```
Pool 1: 4 nodes x 1 x 10TB disk
Pool 2: 4 nodes x 4 x 16TB disks  ← ต่างกันได้!
Pool 3: 4 nodes x 4 x 20TB disks  ← จำนวน disk ต่างได้!
```

---

## ⚠️ Important Rules

1. **เพิ่มเป็น Pool ใหม่** - ไม่ใช่เพิ่ม node เข้า pool เดิม
2. **จำนวน nodes ใน pool ใหม่ต้อง ≥ 4**
3. **ต้อง Stop cluster ก่อนเพิ่ม**
4. **Config ต้องเหมือนกันทุก node**
5. **Disk ใน pool เดียวกันควร size เท่ากัน** (ข้าม pool ต่างได้)

---

## 🚀 Expansion Steps

### Step 1: Edit pools.conf

```bash
nano config/pools.conf
```

Uncomment Pool 2:

```properties
# ============================
# Pool 2: Nodes 5-8
# ============================
POOL2_START=5
POOL2_END=8
POOL2_DISKS=1
POOL2_PATH=/mnt/minio-data

NODE5_IP=10.0.0.8
NODE6_IP=10.0.0.7
NODE7_IP=10.0.0.9
NODE8_IP=10.0.0.6
```

### Step 2: Copy pools.conf to ALL Nodes (เก่า + ใหม่)

```bash
# Copy ไปทุก node (1-8)
for i in 1 2 3 4 5 6 7 8; do
    IP_VAR="NODE${i}_IP"
    # source pools.conf to get IPs
    source config/pools.conf
    scp config/pools.conf root@${!IP_VAR}:~/minio-cloud/config/
done
```

### Step 3: Install MinIO on New Nodes

```bash
# SSH ไป node 5
sudo ./install.sh --node 5 --ip 10.0.0.8

# SSH ไป node 6
sudo ./install.sh --node 6 --ip 10.0.0.7

# SSH ไป node 7
sudo ./install.sh --node 7 --ip 10.0.0.9

# SSH ไป node 8
sudo ./install.sh --node 8 --ip 10.0.0.6
```

### Step 4: Update and Restart ALL Nodes

```bash
# จาก node 1 - อัพเดททุก node
./update-nodes.sh --dry-run    # ดูก่อนว่าจะทำอะไร

./update-nodes.sh --restart    # อัพเดท config + restart ทุก node
```

### Step 5: Verify

```bash
mc admin info myminio

# Should show 8 nodes, 2 pools
```

---

## 📊 After Expansion

### Data Distribution

```
New objects → MinIO เลือก Pool ที่มีพื้นที่ว่างมากที่สุด
Old objects → ยังอยู่ Pool เดิม (ไม่ย้ายอัตโนมัติ)

ตัวอย่าง:
  Pool 1: 80% full (10TB disks)
  Pool 2: 20% full (16TB disks)
  
  → ไฟล์ใหม่จะไป Pool 2 เป็นหลัก
```

### Access จาก Node ไหนก็ได้

```bash
# ไฟล์อยู่ Pool 2 แต่เรียกจาก Pool 1 node ได้
curl http://minio1:9000/files/video.mp4  ✅
curl http://minio5:9000/files/video.mp4  ✅

# MinIO route ให้อัตโนมัติ!
```

---

## ⚠️ Rollback (ถ้าเกิดปัญหา)

```bash
# Stop all
./update-nodes.sh --stop

# Restore old pools.conf (ลบ Pool 2 ออก)
nano config/pools.conf

# Restart only old nodes (1-4)
./update-nodes.sh --restart
```

---

## 📋 Expansion Checklist

- [ ] New nodes installed with same OS
- [ ] Disks mounted (e.g., /mnt/minio-data)
- [ ] pools.conf updated with new pool
- [ ] pools.conf copied to ALL nodes
- [ ] install.sh ran on new nodes
- [ ] update-nodes.sh --restart ran
- [ ] Cluster health verified
- [ ] (Optional) Update Cloudflare DNS

---

## 📊 pools.conf Format Reference

```properties
# Pool definition
POOL<N>_START=<first_node_number>
POOL<N>_END=<last_node_number>
POOL<N>_DISKS=<disks_per_node>        # 1 = single disk, 4 = multi-disk
POOL<N>_PATH=<mount_path>

# Node IPs
NODE<N>_IP=<private_ip>
```

### Examples

**Single disk per node:**
```properties
POOL1_START=1
POOL1_END=4
POOL1_DISKS=1
POOL1_PATH=/mnt/minio-data
# Result: http://minio{1...4}:9000/mnt/minio-data
```

**Multi-disk per node:**
```properties
POOL2_START=5
POOL2_END=8
POOL2_DISKS=4
POOL2_PATH=/data/disk
# Result: http://minio{5...8}:9000/data/disk{1...4}
```
