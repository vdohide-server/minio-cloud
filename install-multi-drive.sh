#!/bin/bash
#
# MinIO Distributed Installation Script - Multi-Drive Edition
# สำหรับ Dedicated Servers ที่มีหลาย disk ต่อเครื่อง
#
# Usage:
#   ./install-multi-drive.sh --node <number> --ip <private-ip>
#
# Example (4 servers x 4 disks):
#   ./install-multi-drive.sh --node 1 --ip 10.0.0.1
#
# Config จะอ่านจาก pools.conf:
#   - POOL1_DISKS=4        (จำนวน disk ต่อเครื่อง)
#   - POOL1_PATH=/mnt/disk (mount path prefix)
#   - POOL1_START/END      (range ของ node numbers)
#

set -e

# ============================================
# Configuration
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/pools.conf"

MINIO_USER="minio-user"
MINIO_GROUP="minio-user"
LOCAL_MINIO="${SCRIPT_DIR}/scripts/minio"
LOCAL_MC="${SCRIPT_DIR}/scripts/mc"
MINIO_BINARY_URL="https://dl.min.io/server/minio/release/linux-amd64/minio"
MC_BINARY_URL="https://dl.min.io/client/mc/release/linux-amd64/mc"

# Defaults (loaded from pools.conf)
NODE_NUMBER=""
PRIVATE_IP=""
TOTAL_NODES="4"
DRIVE_COUNT="4"
MOUNT_PREFIX="/mnt/disk"

# Credentials (loaded from pools.conf)
MINIO_ROOT_USER="admin"
MINIO_ROOT_PASSWORD="changeme123"
MINIO_REGION="cloud"

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
# Parse Arguments
# ============================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --node)
                if [[ -z "$2" ]]; then
                    log_error "--node requires a number"
                fi
                NODE_NUMBER="$2"
                shift 2
                ;;
            --ip)
                if [[ -z "$2" ]]; then
                    log_error "--ip requires an IP address"
                fi
                PRIVATE_IP="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$NODE_NUMBER" ]]; then
        log_error "--node is required"
    fi
    if [[ -z "$PRIVATE_IP" ]]; then
        log_error "--ip is required"
    fi
}

# ============================================
# Load Pool Configuration
# ============================================
load_pool_config() {
    log_info "Loading configuration from pools.conf..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
    fi
    
    source "$CONFIG_FILE"
    
    # Find which pool this node belongs to
    local found_pool=0
    for pool in 1 2 3 4 5; do
        local start_var="POOL${pool}_START"
        local end_var="POOL${pool}_END"
        local disks_var="POOL${pool}_DISKS"
        local path_var="POOL${pool}_PATH"
        
        if [[ -n "${!start_var}" && -n "${!end_var}" ]]; then
            if [[ $NODE_NUMBER -ge ${!start_var} && $NODE_NUMBER -le ${!end_var} ]]; then
                POOL_NUMBER=$pool
                POOL_START=${!start_var}
                POOL_END=${!end_var}
                DRIVE_COUNT=${!disks_var:-1}
                MOUNT_PREFIX=${!path_var:-/mnt/disk}
                TOTAL_NODES=$(( POOL_END - POOL_START + 1 ))
                found_pool=1
                break
            fi
        fi
    done
    
    if [[ $found_pool -eq 0 ]]; then
        log_error "Node $NODE_NUMBER not found in any pool in pools.conf"
    fi
    
    log_success "Node $NODE_NUMBER is in Pool $POOL_NUMBER (nodes ${POOL_START}-${POOL_END}, ${DRIVE_COUNT} disks each)"
}

show_help() {
    echo "MinIO Multi-Drive Installation Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Required Options:"
    echo "  --node NUMBER       Node number (from pools.conf)"
    echo "  --ip IP             Private IP address of this node"
    echo ""
    echo "Optional:"
    echo "  --help              Show this help"
    echo ""
    echo "Configuration is read from config/pools.conf:"
    echo "  POOL1_START/END     Node number range"
    echo "  POOL1_DISKS         Number of disks per node (default: 4)"
    echo "  POOL1_PATH          Mount path prefix (default: /mnt/disk)"
    echo ""
    echo "Example:"
    echo "  # For 4 servers x 4 disks cluster"
    echo "  $0 --node 1 --ip 10.0.0.1"
    echo "  $0 --node 2 --ip 10.0.0.2"
    echo "  $0 --node 3 --ip 10.0.0.3"
    echo "  $0 --node 4 --ip 10.0.0.4"
    echo ""
    echo "Drive Setup (before running this script):"
    echo "  Mount drives as: /mnt/disk1, /mnt/disk2, /mnt/disk3, /mnt/disk4"
}

# ============================================
# Check Prerequisites
# ============================================
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
    fi

    # For multi-disk setup, check each drive is mounted
    if [[ $DRIVE_COUNT -gt 1 ]]; then
        local missing_drives=0
        for i in $(seq 1 $DRIVE_COUNT); do
            local mount_path="${MOUNT_PREFIX}${i}"
            if ! mountpoint -q "${mount_path}" 2>/dev/null; then
                log_warn "${mount_path} is not mounted"
                missing_drives=1
            else
                log_success "${mount_path} is mounted"
            fi
        done
        
        if [[ $missing_drives -eq 1 ]]; then
            echo ""
            echo "=========================================="
            echo "DISK SETUP REQUIRED"
            echo "=========================================="
            echo ""
            echo "Mount your drives first. Example for 4x 10TB HDDs:"
            echo ""
            echo "  # Format drives (XFS recommended)"
            echo "  mkfs.xfs -f /dev/sdb"
            echo "  mkfs.xfs -f /dev/sdc"
            echo "  mkfs.xfs -f /dev/sdd"
            echo "  mkfs.xfs -f /dev/sde"
            echo ""
            echo "  # Create mount points"
            echo "  mkdir -p /mnt/disk{1..4}"
            echo ""
            echo "  # Mount drives"
            echo "  mount /dev/sdb /mnt/disk1"
            echo "  mount /dev/sdc /mnt/disk2"
            echo "  mount /dev/sdd /mnt/disk3"
            echo "  mount /dev/sde /mnt/disk4"
            echo ""
            echo "  # Add to /etc/fstab for persistence:"
            echo "  /dev/sdb /mnt/disk1 xfs defaults,noatime 0 0"
            echo "  /dev/sdc /mnt/disk2 xfs defaults,noatime 0 0"
            echo "  /dev/sdd /mnt/disk3 xfs defaults,noatime 0 0"
            echo "  /dev/sde /mnt/disk4 xfs defaults,noatime 0 0"
            echo ""
            read -p "Continue anyway? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        # Single disk setup
        if [[ ! -d "$MOUNT_PREFIX" ]]; then
            log_warn "${MOUNT_PREFIX} directory does not exist"
        fi
    fi

    log_success "Prerequisites check passed"
}

# ============================================
# Create User
# ============================================
create_user() {
    log_info "Creating MinIO user..."

    if id "$MINIO_USER" &>/dev/null; then
        log_warn "User $MINIO_USER already exists"
    else
        useradd -r -s /sbin/nologin "$MINIO_USER"
        log_success "User $MINIO_USER created"
    fi
}

# ============================================
# Setup Drives
# ============================================
setup_drives() {
    log_info "Setting up drive directories..."

    if [[ $DRIVE_COUNT -gt 1 ]]; then
        # Multi-disk: /mnt/disk1, /mnt/disk2, etc.
        for i in $(seq 1 $DRIVE_COUNT); do
            local drive_path="${MOUNT_PREFIX}${i}"
            mkdir -p "${drive_path}"
            chown -R ${MINIO_USER}:${MINIO_GROUP} "${drive_path}"
            chmod 750 "${drive_path}"
            log_success "Drive ${i}: ${drive_path} ready"
        done
    else
        # Single disk: /mnt/minio-data
        mkdir -p "${MOUNT_PREFIX}"
        chown -R ${MINIO_USER}:${MINIO_GROUP} "${MOUNT_PREFIX}"
        chmod 750 "${MOUNT_PREFIX}"
        log_success "Drive: ${MOUNT_PREFIX} ready"
    fi
}

# ============================================
# Install MinIO
# ============================================
install_minio() {
    log_info "Installing MinIO server..."

    if [[ -f /usr/local/bin/minio ]]; then
        log_warn "MinIO already installed"
        return
    fi

    # Try local binary first
    if [[ -f "$LOCAL_MINIO" ]]; then
        log_info "Using local MinIO binary..."
        cp "$LOCAL_MINIO" /usr/local/bin/minio
        chmod +x /usr/local/bin/minio
        log_success "MinIO installed from local binary"
    else
        log_info "Downloading MinIO..."
        wget -q --show-progress "$MINIO_BINARY_URL" -O /usr/local/bin/minio
        chmod +x /usr/local/bin/minio
        log_success "MinIO downloaded and installed"
    fi
}

# ============================================
# Install MC (MinIO Client)
# ============================================
install_mc() {
    log_info "Installing MinIO client (mc)..."

    if [[ -f /usr/local/bin/mc ]]; then
        log_warn "mc already installed"
        return
    fi

    # Try local binary first
    if [[ -f "$LOCAL_MC" ]]; then
        log_info "Using local mc binary..."
        cp "$LOCAL_MC" /usr/local/bin/mc
        chmod +x /usr/local/bin/mc
        log_success "mc installed from local binary"
    else
        log_info "Downloading mc..."
        wget -q --show-progress "$MC_BINARY_URL" -O /usr/local/bin/mc
        chmod +x /usr/local/bin/mc
        log_success "mc downloaded and installed"
    fi
}

# ============================================
# Configure Hosts
# ============================================
configure_hosts() {
    log_info "Configuring /etc/hosts..."

    # Add entries for all nodes in this pool
    for i in $(seq $POOL_START $POOL_END); do
        local ip_var="NODE${i}_IP"
        local ip="${!ip_var}"
        
        if [[ -n "$ip" ]]; then
            # Remove existing entry
            sed -i "/minio${i}$/d" /etc/hosts
            # Add new entry
            echo "${ip} minio${i}" >> /etc/hosts
            log_success "Added minio${i} -> ${ip}"
        fi
    done

    log_success "/etc/hosts configured"
}

# ============================================
# Create Environment File
# ============================================
create_env_file() {
    log_info "Creating MinIO environment file..."

    # Build volumes string based on disk count
    local volumes=""
    if [[ $DRIVE_COUNT -gt 1 ]]; then
        # Multi-disk: http://minio{1...4}:9000/mnt/disk{1...4}
        volumes="http://minio{${POOL_START}...${POOL_END}}:9000${MOUNT_PREFIX}{1...${DRIVE_COUNT}}"
    else
        # Single disk: http://minio{1...4}:9000/mnt/minio-data
        volumes="http://minio{${POOL_START}...${POOL_END}}:9000${MOUNT_PREFIX}"
    fi
    
    local total_drives=$((TOTAL_NODES * DRIVE_COUNT))

    cat > /etc/default/minio << EOF
# MinIO Environment Configuration
# Generated by install-multi-drive.sh
# Node: ${NODE_NUMBER} | Pool: ${POOL_NUMBER} (nodes ${POOL_START}-${POOL_END})
# ${TOTAL_NODES} nodes x ${DRIVE_COUNT} drives = ${total_drives} total drives

# Credentials
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}

# Distributed cluster volumes
MINIO_VOLUMES="${volumes}"

# Server URL (this node)
MINIO_SERVER_URL="http://minio${NODE_NUMBER}:9000"

# Console settings
MINIO_CONSOLE_ADDRESS=":9001"
MINIO_BROWSER_REDIRECT_URL="http://minio${NODE_NUMBER}:9001"

# Site settings
MINIO_SITE_REGION=${MINIO_SITE_REGION:-cloud}
MINIO_SITE_NAME=${MINIO_SITE_NAME:-minio-cluster}

# Performance tuning
MINIO_API_REQUESTS_MAX=10000
MINIO_API_REQUESTS_DEADLINE=2m
EOF

    chmod 600 /etc/default/minio
    log_success "Environment file created at /etc/default/minio"
    
    echo ""
    echo "MINIO_VOLUMES = ${volumes}"
    echo ""
}

# ============================================
# Create Systemd Service
# ============================================
create_systemd_service() {
    log_info "Creating systemd service..."

    # Build ReadWritePaths based on disk count
    local rw_paths=""
    if [[ $DRIVE_COUNT -gt 1 ]]; then
        for i in $(seq 1 $DRIVE_COUNT); do
            rw_paths="${rw_paths} ${MOUNT_PREFIX}${i}"
        done
    else
        rw_paths="${MOUNT_PREFIX}"
    fi

    cat > /etc/systemd/system/minio.service << EOF
[Unit]
Description=MinIO Object Storage
Documentation=https://min.io/docs/minio/linux/index.html
Wants=network-online.target
After=network-online.target
AssertFileIsExecutable=/usr/local/bin/minio

[Service]
Type=notify
WorkingDirectory=/usr/local

User=minio-user
Group=minio-user

EnvironmentFile=-/etc/default/minio
ExecStart=/usr/local/bin/minio server \$MINIO_VOLUMES --console-address \$MINIO_CONSOLE_ADDRESS

# Memory limits (adjust based on RAM)
MemoryMax=24G
MemoryHigh=20G

# Restart policy
Restart=always
RestartSec=10

# Limits
LimitNOFILE=1048576
LimitNPROC=1048576
TasksMax=infinity
TimeoutStartSec=infinity
TimeoutStopSec=infinity

# Security
ProtectSystem=full
ReadWritePaths=${rw_paths}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Systemd service created"
}

# ============================================
# Start MinIO
# ============================================
start_minio() {
    log_info "Starting MinIO service..."

    systemctl enable minio

    echo ""
    echo -e "${YELLOW}NOTE: MinIO will not start until all nodes are configured!${NC}"
    echo ""
    echo "After configuring ALL nodes:"
    echo "  1. Make sure /etc/hosts has all minio1-minio${TOTAL_NODES} entries on each node"
    echo "  2. Run: systemctl start minio"
    echo "  3. Check: systemctl status minio"
    echo ""

    read -p "Start MinIO now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl start minio || log_warn "MinIO may not start until all nodes are ready"
    fi
}

# ============================================
# Print Summary
# ============================================
print_summary() {
    local total_drives=$((TOTAL_NODES * DRIVE_COUNT))
    local parity=$((total_drives / 2))
    
    # Calculate capacity (assuming 10TB drives for dedicated servers)
    local drive_size=10
    if [[ $DRIVE_COUNT -eq 1 ]]; then
        drive_size=1  # VPS typically 1TB or less
    fi
    local raw_tb=$((total_drives * drive_size))
    local usable_tb=$((raw_tb / 2))

    echo ""
    echo "============================================"
    echo -e "${GREEN}MinIO Node ${NODE_NUMBER} Installation Complete!${NC}"
    echo "============================================"
    echo ""
    echo "Pool Configuration:"
    echo "  Pool number:     ${POOL_NUMBER}"
    echo "  Nodes:           ${POOL_START} - ${POOL_END} (${TOTAL_NODES} nodes)"
    echo "  Drives per node: ${DRIVE_COUNT}"
    echo "  Total drives:    ${total_drives}"
    echo "  Erasure Coding:  EC:$((total_drives / 2))"
    echo "  Fault tolerance: $((total_drives / 2)) drives"
    echo ""
    echo "This Node:"
    echo "  Node number:     ${NODE_NUMBER}"
    echo "  Private IP:      ${PRIVATE_IP}"
    echo "  Hostname:        minio${NODE_NUMBER}"
    if [[ $DRIVE_COUNT -gt 1 ]]; then
        echo "  Drives:          ${MOUNT_PREFIX}1 - ${MOUNT_PREFIX}${DRIVE_COUNT}"
    else
        echo "  Data path:       ${MOUNT_PREFIX}"
    fi
    echo ""
    echo "URLs (after cluster is running):"
    echo "  S3 API:          http://minio${NODE_NUMBER}:9000"
    echo "  Console:         http://minio${NODE_NUMBER}:9001"
    echo ""
    echo "Credentials:"
    echo "  Username:        ${MINIO_ROOT_USER}"
    echo "  Password:        ${MINIO_ROOT_PASSWORD}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Run this script on ALL other nodes (${POOL_START}-${POOL_END})"
    echo "  2. Start MinIO on all nodes: systemctl start minio"
    echo "  3. Check status: systemctl status minio"
    echo "  4. Setup mc:"
    echo "     mc alias set myminio http://minio${NODE_NUMBER}:9000 ${MINIO_ROOT_USER} '${MINIO_ROOT_PASSWORD}'"
    echo "  5. Check cluster: mc admin info myminio"
    echo ""
}

# ============================================
# Main
# ============================================
main() {
    echo ""
    echo "=========================================="
    echo "  MinIO Multi-Drive Installation Script"
    echo "=========================================="
    echo ""

    parse_args "$@"
    load_pool_config
    check_prerequisites
    create_user
    setup_drives
    install_minio
    install_mc
    configure_hosts
    create_env_file
    create_systemd_service
    start_minio
    print_summary
}

main "$@"
