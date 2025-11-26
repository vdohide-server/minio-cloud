#!/bin/bash
#
# Setup Drives Script for MinIO Multi-Drive
# Formats and mounts 4 HDDs for MinIO storage
#
# Usage:
#   ./setup-drives.sh
#
# WARNING: This script will FORMAT drives! Make sure they are the correct ones!
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

# ============================================
# List Available Drives
# ============================================
list_drives() {
    echo ""
    echo "Available drives:"
    echo "================="
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep disk
    echo ""
}

# ============================================
# Setup Single Drive
# ============================================
setup_drive() {
    local device=$1
    local mount_point=$2
    local disk_num=$3
    
    echo ""
    log_info "Setting up ${device} -> ${mount_point}"
    
    # Check if already mounted
    if mountpoint -q "$mount_point" 2>/dev/null; then
        log_warn "${mount_point} already mounted, skipping"
        return 0
    fi
    
    # Confirm format
    echo -e "${RED}WARNING: This will ERASE all data on ${device}!${NC}"
    read -p "Format ${device}? (yes/no) " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_warn "Skipping ${device}"
        return 0
    fi
    
    # Create partition
    log_info "Creating partition on ${device}..."
    parted -s "$device" mklabel gpt
    parted -s "$device" mkpart primary xfs 0% 100%
    
    # Wait for partition to appear
    sleep 2
    
    # Format
    local partition="${device}1"
    if [[ ! -b "$partition" ]]; then
        partition="${device}p1"  # for nvme drives
    fi
    
    log_info "Formatting ${partition} with XFS..."
    mkfs.xfs -f "$partition"
    
    # Create mount point
    mkdir -p "$mount_point"
    
    # Mount
    mount "$partition" "$mount_point"
    
    # Add to fstab
    local uuid=$(blkid -s UUID -o value "$partition")
    if ! grep -q "$uuid" /etc/fstab; then
        echo "UUID=${uuid} ${mount_point} xfs defaults,noatime 0 0" >> /etc/fstab
        log_success "Added to /etc/fstab"
    fi
    
    # Set ownership
    chown minio-user:minio-user "$mount_point" 2>/dev/null || true
    
    log_success "${device} mounted at ${mount_point}"
}

# ============================================
# Auto Detect Drives
# ============================================
auto_setup() {
    log_info "Auto-detecting drives..."
    
    # Find all drives except the system drive
    local system_drive=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//')
    local drives=($(lsblk -d -n -o NAME,TYPE | grep disk | awk '{print "/dev/"$1}' | grep -v "$system_drive"))
    
    echo ""
    echo "Detected drives (excluding system):"
    for d in "${drives[@]}"; do
        echo "  $d ($(lsblk -d -n -o SIZE $d))"
    done
    echo ""
    
    if [[ ${#drives[@]} -lt 4 ]]; then
        log_warn "Found only ${#drives[@]} drives. Expected 4 for MinIO multi-drive setup."
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    local disk_num=1
    for drive in "${drives[@]}"; do
        if [[ $disk_num -gt 4 ]]; then
            break
        fi
        setup_drive "$drive" "/mnt/disk${disk_num}" "$disk_num"
        ((disk_num++))
    done
}

# ============================================
# Manual Setup
# ============================================
manual_setup() {
    list_drives
    
    echo "Enter drive devices (e.g., /dev/sda /dev/sdb /dev/sdc /dev/sdd):"
    read -p "Drives: " -a drives
    
    if [[ ${#drives[@]} -ne 4 ]]; then
        log_error "Please provide exactly 4 drives"
    fi
    
    local disk_num=1
    for drive in "${drives[@]}"; do
        setup_drive "$drive" "/mnt/disk${disk_num}" "$disk_num"
        ((disk_num++))
    done
}

# ============================================
# Verify Setup
# ============================================
verify_setup() {
    echo ""
    echo "============================================"
    echo "Drive Setup Summary:"
    echo "============================================"
    echo ""
    
    for i in 1 2 3 4; do
        local mount_point="/mnt/disk${i}"
        if mountpoint -q "$mount_point" 2>/dev/null; then
            local size=$(df -h "$mount_point" | tail -1 | awk '{print $2}')
            echo -e "  ${GREEN}✓${NC} /mnt/disk${i} - ${size}"
        else
            echo -e "  ${RED}✗${NC} /mnt/disk${i} - NOT MOUNTED"
        fi
    done
    
    echo ""
    df -h /mnt/disk* 2>/dev/null || true
    echo ""
}

# ============================================
# Main
# ============================================
main() {
    echo ""
    echo "=========================================="
    echo "  MinIO Drive Setup Script"
    echo "=========================================="
    echo ""
    
    # Check root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
    fi
    
    # Install xfsprogs if not present
    if ! command -v mkfs.xfs &> /dev/null; then
        log_info "Installing xfsprogs..."
        apt update && apt install -y xfsprogs parted
    fi
    
    # Create minio user if not exists
    if ! id "minio-user" &>/dev/null; then
        useradd -r -s /sbin/nologin minio-user
    fi
    
    echo "Choose setup mode:"
    echo "  1) Auto-detect drives"
    echo "  2) Manual selection"
    echo "  3) Just verify current setup"
    echo ""
    read -p "Choice [1-3]: " choice
    
    case $choice in
        1) auto_setup ;;
        2) manual_setup ;;
        3) ;;
        *) log_error "Invalid choice" ;;
    esac
    
    verify_setup
    
    echo ""
    log_success "Drive setup complete!"
    echo ""
    echo "Next: Run install-multi-drive.sh to install MinIO"
    echo ""
}

main "$@"
