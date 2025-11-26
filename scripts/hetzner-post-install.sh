#!/bin/bash
#
# Hetzner Post-Install Script for MinIO
# รันหลังจาก installimage เสร็จและ reboot แล้ว
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/vdohide-server/minio-cloud/main/scripts/hetzner-post-install.sh | bash
#
# หรือ:
#   ./scripts/hetzner-post-install.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "=========================================="
echo "  Hetzner Post-Install Script for MinIO"
echo "=========================================="
echo ""

# ============================================
# Step 1: Update System
# ============================================
log_info "Updating system..."
apt-get update && apt-get upgrade -y
log_success "System updated"

# ============================================
# Step 2: Install Required Packages
# ============================================
log_info "Installing required packages..."
apt-get install -y \
    xfsprogs \
    git \
    curl \
    wget \
    htop \
    iotop \
    net-tools \
    vim
log_success "Packages installed"

# ============================================
# Step 3: Detect Data Disks
# ============================================
log_info "Detecting data disks..."

echo ""
echo "Available disks:"
lsblk -d -o NAME,SIZE,TYPE,MODEL | grep disk
echo ""

# Find disks that are NOT mounted (data disks)
DATA_DISKS=()
while read -r disk; do
    # Skip if disk has partitions that are mounted
    if ! lsblk "/dev/$disk" | grep -q "part.*/" ; then
        # Skip small disks (< 500GB, likely OS disk)
        size_bytes=$(lsblk -b -d -o SIZE "/dev/$disk" | tail -1)
        size_tb=$((size_bytes / 1000000000000))
        if [[ $size_tb -ge 1 ]]; then
            DATA_DISKS+=("$disk")
        fi
    fi
done < <(lsblk -d -o NAME | grep -E '^sd[b-z]$|^nvme[0-9]n[0-9]$' | grep -v "$(lsblk -o NAME,MOUNTPOINT | grep '/$' | awk '{print $1}' | sed 's/[0-9]*$//' | head -1)")

if [[ ${#DATA_DISKS[@]} -eq 0 ]]; then
    log_warn "No data disks detected automatically"
    echo ""
    echo "Please enter disk names manually (e.g., sdb sdc sdd sde):"
    read -r -a DATA_DISKS
fi

echo ""
echo "Data disks found: ${DATA_DISKS[*]}"
echo ""

# ============================================
# Step 4: Format and Mount Disks
# ============================================
read -p "Format and mount these disks? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    DISK_NUM=1
    for disk in "${DATA_DISKS[@]}"; do
        log_info "Formatting /dev/$disk..."
        mkfs.xfs -f "/dev/$disk"
        
        log_info "Mounting /dev/$disk to /mnt/disk$DISK_NUM..."
        mkdir -p "/mnt/disk$DISK_NUM"
        mount "/dev/$disk" "/mnt/disk$DISK_NUM"
        
        # Add to fstab
        if ! grep -q "/dev/$disk" /etc/fstab; then
            echo "/dev/$disk /mnt/disk$DISK_NUM xfs defaults,noatime 0 0" >> /etc/fstab
        fi
        
        log_success "/dev/$disk -> /mnt/disk$DISK_NUM"
        DISK_NUM=$((DISK_NUM + 1))
    done
fi

# ============================================
# Step 5: Show Summary
# ============================================
echo ""
echo "=========================================="
echo -e "${GREEN}Post-Install Complete!${NC}"
echo "=========================================="
echo ""
echo "Mounted disks:"
df -h /mnt/disk* 2>/dev/null || echo "  No disks mounted"
echo ""
echo "Next steps:"
echo "  1. Clone minio-cloud repo:"
echo "     git clone https://github.com/vdohide-server/minio-cloud.git"
echo ""
echo "  2. Edit config/pools.conf"
echo ""
echo "  3. Install MinIO:"
echo "     cd minio-cloud"
echo "     sudo ./install-multi-drive.sh --node 1 --ip 10.0.0.1"
echo ""
