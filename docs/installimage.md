# Hetzner Dedicated Server Setup Guide

## 📋 Overview

ขั้นตอนการติดตั้ง Hetzner Dedicated Server สำหรับ MinIO Cluster

| ขั้นตอน | เวลา | หมายเหตุ |
|---------|------|----------|
| 1. ติดตั้ง OS | ~15 นาที | ใช้ installimage |
| 2. Mount Disks | ~5 นาที | Format XFS |
| 3. ตั้งค่า vSwitch | ~10 นาที | Private network |
| 4. ตรวจสอบ | ~5 นาที | Verify ก่อนติดตั้ง MinIO |

---

## Step 1: ติดตั้ง OS (installimage)

### 1.1 Boot เข้า Rescue Mode

1. Login [robot.hetzner.com](https://robot.hetzner.com)
2. ไปที่ **Servers** → เลือก Server
3. **Rescue** tab → **Activate Rescue System**
4. เลือก **Linux 64bit**
5. กด **Activate**
6. ไปที่ **Reset** tab → กด **Execute** (Hardware Reset)
7. รอ 2-3 นาที

### 1.2 SSH เข้า Rescue Mode

```bash
ssh root@YOUR_SERVER_IP
# Password: จะแสดงตอน Activate Rescue
```

### 1.3 รัน installimage

```bash
installimage
```

### 1.4 เลือก Image

```
Ubuntu 24.04 LTS (noble) - recommended
```

### 1.5 แก้ไข Config

**ลบทุกอย่าง** แล้ว copy config นี้ไปวาง:

```bash
# ============================================
# MinIO Server - installimage config
# ============================================

SWRAID 0
SWRAIDLEVEL 0

HOSTNAME minio1

PART /boot  ext3  1024M
PART lvm    vg0   all

LV vg0 root  /     ext4  50G
LV vg0 swap  swap  swap  32G

IMAGE /root/.oldroot/nfs/images/Ubuntu-2404-noble-amd64-base.tar.gz
```

> ⚠️ **สำคัญ:** เปลี่ยน `HOSTNAME` ตาม node: `minio1`, `minio2`, `minio3`, `minio4`

### 1.6 Save และ Install

- กด **F2** = Save
- กด **F10** = Exit
- พิมพ์ **yes** เพื่อยืนยันการ format
- รอ ~10-15 นาที
- พิมพ์ **reboot** เมื่อเสร็จ

### 1.7 SSH เข้า OS ใหม่

```bash
ssh root@YOUR_SERVER_IP
# Password: เหมือน Rescue Mode
```

---

## Step 2: Mount Data Disks

### 2.1 ดู Disks ทั้งหมด

```bash
lsblk
```

**ตัวอย่าง output (4x 10TB HDDs):**
```
NAME         MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda            8:0    0  9.1T  0 disk              ← Data disk 1
sdb            8:16   0  9.1T  0 disk              ← Data disk 2
sdc            8:32   0  9.1T  0 disk              ← OS disk (มี partitions)
├─sdc1         8:33   0    1G  0 part /boot
├─sdc2         8:34   0  9.1T  0 part
│ ├─vg0-root 252:0    0   50G  0 lvm  /
│ └─vg0-swap 252:1    0   32G  0 lvm  [SWAP]
└─sdc3         8:35   0    1M  0 part
sdd            8:48   0  9.1T  0 disk              ← Data disk 3
```

> ⚠️ **หมายเหตุ:** OS จะติดตั้งบน disk ตัวใดตัวหนึ่ง (ในตัวอย่างคือ sdc)
> แต่เราสามารถใช้พื้นที่ว่างที่เหลือใน LVM ได้!

---

### 2.2 วิธี Mount: กรณี OS อยู่บน HDD ตัวหนึ่ง (แนะนำ)

เมื่อ OS ติดตั้งบน HDD ตัวหนึ่ง จะเหลือพื้นที่ว่างใน LVM (~9TB)
เราสามารถสร้าง LV ใหม่สำหรับ MinIO ได้

```bash
# ดูพื้นที่ว่างใน VG
vgdisplay vg0 | grep Free
# Expected: Free  PE / Size   xxxxx / ~9.xx TiB
```

**Full Commands (Copy-Paste ได้เลย):**

```bash
# 1. Format 3 HDDs ที่ว่าง (ไม่ใช่ OS disk)
mkfs.xfs -f /dev/sda
mkfs.xfs -f /dev/sdb
mkfs.xfs -f /dev/sdd

# 2. สร้าง LV จากพื้นที่ว่างบน OS disk
lvcreate -l 100%FREE -n minio vg0
mkfs.xfs -f /dev/vg0/minio

# 3. สร้าง mount points
mkdir -p /mnt/disk{1..4}

# 4. Mount ทั้ง 4 disks
mount /dev/sda /mnt/disk1
mount /dev/sdb /mnt/disk2
mount /dev/sdd /mnt/disk3
mount /dev/vg0/minio /mnt/disk4

# 5. เพิ่มใน fstab (auto-mount หลัง reboot)
cat >> /etc/fstab << 'EOF'
/dev/sda /mnt/disk1 xfs defaults,noatime 0 0
/dev/sdb /mnt/disk2 xfs defaults,noatime 0 0
/dev/sdd /mnt/disk3 xfs defaults,noatime 0 0
/dev/vg0/minio /mnt/disk4 xfs defaults,noatime 0 0
EOF

# 6. Verify
df -h /mnt/disk*
```

**Expected output:**
```
Filesystem             Size  Used Avail Use% Mounted on
/dev/sda               9.1T  179G  9.0T   2% /mnt/disk1
/dev/sdb               9.1T  179G  9.0T   2% /mnt/disk2
/dev/sdd               9.1T  179G  9.0T   2% /mnt/disk3
/dev/mapper/vg0-minio  9.1T  177G  8.9T   2% /mnt/disk4
```

---

### 2.3 วิธี Mount: กรณีมี NVMe/SSD แยกสำหรับ OS

ถ้า Server มี NVMe/SSD สำหรับ OS จะมี HDD 4 ตัวว่างทั้งหมด

```bash
# Format ทุก HDD
mkfs.xfs -f /dev/sda
mkfs.xfs -f /dev/sdb
mkfs.xfs -f /dev/sdc
mkfs.xfs -f /dev/sdd

# สร้าง mount points
mkdir -p /mnt/disk{1..4}

# Mount
mount /dev/sda /mnt/disk1
mount /dev/sdb /mnt/disk2
mount /dev/sdc /mnt/disk3
mount /dev/sdd /mnt/disk4

# เพิ่มใน fstab
cat >> /etc/fstab << 'EOF'
/dev/sda /mnt/disk1 xfs defaults,noatime 0 0
/dev/sdb /mnt/disk2 xfs defaults,noatime 0 0
/dev/sdc /mnt/disk3 xfs defaults,noatime 0 0
/dev/sdd /mnt/disk4 xfs defaults,noatime 0 0
EOF

# Verify
df -h /mnt/disk*
```

---

### 2.4 สรุป Disk Layout

| Scenario | Disk 1 | Disk 2 | Disk 3 | Disk 4 |
|----------|--------|--------|--------|--------|
| **OS บน HDD** | /dev/sda | /dev/sdb | /dev/sdd | /dev/vg0/minio |
| **OS บน NVMe** | /dev/sda | /dev/sdb | /dev/sdc | /dev/sdd |

---

## Step 3: ตั้งค่า vSwitch (Private Network)

### 3.1 สร้าง vSwitch (ทำครั้งเดียว)

1. Login [robot.hetzner.com](https://robot.hetzner.com)
2. ไปที่ **vSwitches** (เมนูซ้าย)
3. กด **Create vSwitch**

```
Name:       minio-vswitch
VLAN ID:    4000        (หรือเลขอื่น 1-4095)
```

4. กด **Create vSwitch**

### 3.2 เพิ่ม Servers เข้า vSwitch

1. ไปที่ vSwitch ที่สร้าง
2. กด **Add Server**
3. เลือกทุก Server ที่จะใช้ MinIO
4. กด **Add**

### 3.3 หา Network Interface Name

```bash
ip link show
```

ตัวอย่าง output:
```
1: lo: ...
2: enp0s31f6: ...    ← Interface หลัก
3: enp7s0: ...
```

> ใช้ interface ที่ **ไม่ใช่** `lo` - ปกติจะเป็น `enp0s31f6` หรือ `eno1`

### 3.4 สร้าง Netplan Config

```bash
nano /etc/netplan/99-vswitch.yaml
```

วาง config นี้:

```yaml
network:
  version: 2
  vlans:
    vlan4000:
      id: 4000
      link: enp0s31f6
      mtu: 1400
      addresses:
        - 10.0.0.1/24
```

> ⚠️ **แก้ไข:**
> - `link`: ใส่ชื่อ interface ของเครื่อง
> - `addresses`: เปลี่ยน IP ตาม node

| Server | IP |
|--------|-----|
| minio1 | 10.0.0.1/24 |
| minio2 | 10.0.0.2/24 |
| minio3 | 10.0.0.3/24 |
| minio4 | 10.0.0.4/24 |

### 3.5 Apply Netplan

```bash
netplan apply
```

### 3.6 Verify vSwitch IP

```bash
ip addr show vlan4000
```

Expected output:
```
4: vlan4000@enp0s31f6: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1400
    inet 10.0.0.1/24 brd 10.0.0.255 scope global vlan4000
```

---

## Step 4: ตรวจสอบความพร้อม

### 4.1 Checklist Script

รัน script นี้เพื่อตรวจสอบ:

```bash
#!/bin/bash
echo "=========================================="
echo "  MinIO Server Readiness Check"
echo "=========================================="
echo ""

# Check hostname
echo -n "1. Hostname: "
hostname

# Check OS
echo -n "2. OS: "
cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2

# Check disks
echo ""
echo "3. Data Disks:"
for i in 1 2 3 4; do
    if mountpoint -q /mnt/disk$i 2>/dev/null; then
        size=$(df -h /mnt/disk$i | tail -1 | awk '{print $2}')
        echo "   ✅ /mnt/disk$i mounted ($size)"
    else
        echo "   ❌ /mnt/disk$i NOT mounted"
    fi
done

# Check vSwitch
echo ""
echo "4. vSwitch (Private Network):"
if ip addr show vlan4000 &>/dev/null; then
    ip=$(ip addr show vlan4000 | grep "inet " | awk '{print $2}')
    echo "   ✅ vlan4000 configured ($ip)"
else
    echo "   ❌ vlan4000 NOT configured"
fi

# Check connectivity to other nodes
echo ""
echo "5. Ping Other Nodes:"
for ip in 10.0.0.1 10.0.0.2 10.0.0.3 10.0.0.4; do
    if ping -c 1 -W 1 $ip &>/dev/null; then
        echo "   ✅ $ip reachable"
    else
        echo "   ⚠️  $ip not reachable (may not be ready yet)"
    fi
done

echo ""
echo "=========================================="
```

### 4.2 Quick Check Commands

```bash
# 1. Check hostname
hostname
# Expected: minio1, minio2, etc.

# 2. Check disks mounted
df -h /mnt/disk*
# Expected: 4 disks mounted

# 3. Check vSwitch IP
ip addr show vlan4000 | grep "inet "
# Expected: inet 10.0.0.X/24

# 4. Ping other nodes
ping -c 3 10.0.0.2
# Expected: 0% packet loss
```

### 4.3 Expected Results

| Check | ✅ Pass | ❌ Fail |
|-------|---------|---------|
| Hostname | `minio1` | `localhost` |
| Disks | 4 disks mounted | Missing mounts |
| vSwitch | `inet 10.0.0.X/24` | No IP |
| Ping | 0% packet loss | 100% packet loss |

---

## Summary Checklist

ทำซ้ำสำหรับแต่ละ Server:

### Server 1 (minio1)
- [ ] installimage with HOSTNAME=minio1
- [ ] Mounted /mnt/disk{1..4}
- [ ] vSwitch IP: 10.0.0.1
- [ ] Ping test passed

### Server 2 (minio2)
- [ ] installimage with HOSTNAME=minio2
- [ ] Mounted /mnt/disk{1..4}
- [ ] vSwitch IP: 10.0.0.2
- [ ] Ping test passed

### Server 3 (minio3)
- [ ] installimage with HOSTNAME=minio3
- [ ] Mounted /mnt/disk{1..4}
- [ ] vSwitch IP: 10.0.0.3
- [ ] Ping test passed

### Server 4 (minio4)
- [ ] installimage with HOSTNAME=minio4
- [ ] Mounted /mnt/disk{1..4}
- [ ] vSwitch IP: 10.0.0.4
- [ ] Ping test passed

---

## Next Step: Install MinIO

เมื่อทุก Server พร้อมแล้ว:

```bash
# บนทุกเครื่อง
git clone https://github.com/vdohide-server/minio-cloud.git
cd minio-cloud

# แก้ config (ทำครั้งเดียว แล้ว copy ไปทุกเครื่อง)
nano config/pools.conf

# ติดตั้ง MinIO
# Server 1
sudo ./install-multi-drive.sh --node 1 --ip 10.0.0.1

# Server 2
sudo ./install-multi-drive.sh --node 2 --ip 10.0.0.2

# Server 3
sudo ./install-multi-drive.sh --node 3 --ip 10.0.0.3

# Server 4
sudo ./install-multi-drive.sh --node 4 --ip 10.0.0.4
```

ดูเพิ่มเติมที่ [multi-drive-setup.md](multi-drive-setup.md)
