# MinIO Multi-Drive Cluster Setup Guide
# 10 Nodes x 4 Drives (400TB raw, ~200TB usable)

## Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    MinIO 10-Node Cluster                                │
│                    400TB Raw / ~200TB Usable                            │
│                    EC:20 (can lose 20 drives or 5 full nodes)           │
└─────────────────────────────────────────────────────────────────────────┘

  Node 1          Node 2          Node 3    ...    Node 10
┌─────────┐    ┌─────────┐    ┌─────────┐       ┌─────────┐
│ disk1   │    │ disk1   │    │ disk1   │       │ disk1   │
│ disk2   │    │ disk2   │    │ disk2   │       │ disk2   │
│ disk3   │    │ disk3   │    │ disk3   │       │ disk3   │
│ disk4   │    │ disk4   │    │ disk4   │       │ disk4   │
└─────────┘    └─────────┘    └─────────┘       └─────────┘
   40TB           40TB           40TB              40TB
```

## Prerequisites

Each node should have:
- 4x 10TB HDD
- Private network connectivity to other nodes
- Ubuntu/Debian Linux

## Step 1: Setup Network

### Create Private Network

On your cloud provider (Hetzner/etc), create a private network:
- Network: 10.0.0.0/16
- Attach all 10 servers

### IP Allocation

| Node | Private IP | Hostname |
|------|------------|----------|
| 1    | 10.0.0.1   | minio1   |
| 2    | 10.0.0.2   | minio2   |
| 3    | 10.0.0.3   | minio3   |
| 4    | 10.0.0.4   | minio4   |
| 5    | 10.0.0.5   | minio5   |
| 6    | 10.0.0.6   | minio6   |
| 7    | 10.0.0.7   | minio7   |
| 8    | 10.0.0.8   | minio8   |
| 9    | 10.0.0.9   | minio9   |
| 10   | 10.0.0.10  | minio10  |

## Step 2: Setup Drives (On Each Node)

```bash
# Download scripts
git clone https://github.com/vdohide-server/minio-cloud.git
cd minio-cloud
chmod +x *.sh scripts/*.sh

# Setup drives (formats and mounts 4 HDDs)
sudo ./scripts/setup-drives.sh
```

This will:
- Format drives as XFS
- Mount to /mnt/disk1, /mnt/disk2, /mnt/disk3, /mnt/disk4
- Add entries to /etc/fstab

## Step 3: Install MinIO (On Each Node)

### Node 1:
```bash
sudo ./install-multi-drive.sh \
  --node 1 \
  --total 10 \
  --ip 10.0.0.1 \
  --drives 4 \
  --user admin \
  --password 'YourSecurePassword123!'
```

### Node 2:
```bash
sudo ./install-multi-drive.sh \
  --node 2 \
  --total 10 \
  --ip 10.0.0.2 \
  --drives 4 \
  --user admin \
  --password 'YourSecurePassword123!'
```

### Node 3-10:
```bash
# Repeat for nodes 3-10 with appropriate --node and --ip values
```

## Step 4: Configure /etc/hosts (On ALL Nodes)

Add to /etc/hosts on EVERY node:

```bash
cat >> /etc/hosts << 'EOF'
10.0.0.1  minio1
10.0.0.2  minio2
10.0.0.3  minio3
10.0.0.4  minio4
10.0.0.5  minio5
10.0.0.6  minio6
10.0.0.7  minio7
10.0.0.8  minio8
10.0.0.9  minio9
10.0.0.10 minio10
EOF
```

## Step 5: Start Cluster

On ALL nodes (can run simultaneously):

```bash
sudo systemctl start minio
sudo systemctl status minio
```

## Step 6: Verify Cluster

```bash
# Setup mc
mc alias set myminio http://minio1:9000 admin 'YourSecurePassword123!'

# Check cluster health
mc admin info myminio

# Expected output:
#   10 Online, 0 Offline
#   40 drives, EC:20
```

## Step 7: Create Buckets

```bash
# Create a bucket for videos
mc mb myminio/videos

# Make it public (optional)
mc anonymous set download myminio/videos
```

## Usage

### Upload Files

```bash
# Single file
mc cp /path/to/video.mp4 myminio/videos/

# Entire folder
mc cp --recursive /path/to/folder/ myminio/videos/

# Sync (like rsync)
mc mirror /path/to/source/ myminio/videos/
```

### Access URLs

- S3 API: http://minio1:9000 (or any node)
- Console: http://minio1:9001

### From Application

```
Endpoint: http://minio1:9000
Access Key: admin
Secret Key: YourSecurePassword123!
Region: cloud
```

## Monitoring

### Check Cluster Status
```bash
mc admin info myminio
```

### Check Drive Health
```bash
mc admin heal myminio --verbose
```

### View Logs
```bash
journalctl -u minio -f
```

## Maintenance

### Replace Failed Drive

1. Stop MinIO on affected node
2. Replace physical drive
3. Format and mount new drive
4. Start MinIO - it will auto-heal

### Add More Nodes (Expansion)

MinIO supports adding server pools:

```bash
# Add 4 more nodes as a new pool
# Edit /etc/default/minio on ALL nodes to include new pool
```

## Troubleshooting

### MinIO Won't Start
```bash
# Check logs
journalctl -u minio --no-pager | tail -50

# Common issues:
# - /etc/hosts not configured on all nodes
# - Drives not mounted
# - Different credentials on nodes
```

### Slow Performance
```bash
# Check network between nodes
iperf3 -s  # on one node
iperf3 -c minio1  # from another

# Should be close to 1Gbps
```

### Healing After Drive Failure
```bash
mc admin heal myminio --recursive
```
