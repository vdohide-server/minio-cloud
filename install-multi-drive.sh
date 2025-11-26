#!/bin/bash
#
# MinIO Distributed Installation Script - Multi-Drive Edition
# For 10 nodes with 4x 10TB HDD each (400TB raw, ~200TB usable)
#
# Usage:
#   ./install-multi-drive.sh --node <number> --total <nodes> --ip <private-ip> --drives <count>
#
# Example:
#   ./install-multi-drive.sh --node 1 --total 10 --ip 10.0.0.1 --drives 4
#

set -e

# ============================================
# Configuration
# ============================================
MINIO_USER="minio-user"
MINIO_GROUP="minio-user"
MINIO_BINARY_URL="https://dl.min.io/server/minio/release/linux-amd64/minio"
MC_BINARY_URL="https://dl.min.io/client/mc/release/linux-amd64/mc"

# Defaults
NODE_NUMBER=""
TOTAL_NODES="10"
PRIVATE_IP=""
DRIVE_COUNT="4"
MOUNT_PREFIX="/mnt/disk"

# Credentials (CHANGE THESE!)
MINIO_ROOT_USER="admin"
MINIO_ROOT_PASSWORD="ChangeMe123!"
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
            --total)
                if [[ -z "$2" ]]; then
                    log_error "--total requires a number"
                fi
                TOTAL_NODES="$2"
                shift 2
                ;;
            --ip)
                if [[ -z "$2" ]]; then
                    log_error "--ip requires an IP address"
                fi
                PRIVATE_IP="$2"
                shift 2
                ;;
            --drives)
                if [[ -z "$2" ]]; then
                    log_error "--drives requires a number"
                fi
                DRIVE_COUNT="$2"
                shift 2
                ;;
            --user)
                if [[ -z "$2" ]]; then
                    log_error "--user requires a username"
                fi
                MINIO_ROOT_USER="$2"
                shift 2
                ;;
            --password)
                if [[ -z "$2" ]]; then
                    log_error "--password requires a password"
                fi
                MINIO_ROOT_PASSWORD="$2"
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

show_help() {
    echo "MinIO Multi-Drive Installation Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Required Options:"
    echo "  --node NUMBER       Node number (1-10)"
    echo "  --ip IP             Private IP address of this node"
    echo ""
    echo "Optional:"
    echo "  --total NUMBER      Total number of nodes (default: 10)"
    echo "  --drives NUMBER     Number of drives per node (default: 4)"
    echo "  --user USERNAME     MinIO root username (default: admin)"
    echo "  --password PASS     MinIO root password (default: ChangeMe123!)"
    echo "  --help              Show this help"
    echo ""
    echo "Example:"
    echo "  $0 --node 1 --total 10 --ip 10.0.0.1 --drives 4"
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

    # Check drives are mounted
    for i in $(seq 1 $DRIVE_COUNT); do
        if ! mountpoint -q "${MOUNT_PREFIX}${i}" 2>/dev/null; then
            log_warn "${MOUNT_PREFIX}${i} is not mounted"
            echo ""
            echo "Please mount your drives first. Example:"
            echo "  mkfs.xfs /dev/sda1"
            echo "  mkdir -p ${MOUNT_PREFIX}${i}"
            echo "  mount /dev/sda1 ${MOUNT_PREFIX}${i}"
            echo ""
            echo "Add to /etc/fstab for persistence:"
            echo "  /dev/sda1 ${MOUNT_PREFIX}1 xfs defaults,noatime 0 0"
            echo ""
            read -p "Continue anyway? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    done

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

    for i in $(seq 1 $DRIVE_COUNT); do
        local drive_path="${MOUNT_PREFIX}${i}"
        
        # Create minio data directory on each drive
        mkdir -p "${drive_path}/minio"
        chown -R ${MINIO_USER}:${MINIO_GROUP} "${drive_path}/minio"
        chmod 750 "${drive_path}/minio"
        
        log_success "Drive ${i}: ${drive_path}/minio ready"
    done
}

# ============================================
# Install MinIO
# ============================================
install_minio() {
    log_info "Installing MinIO server..."

    if [[ -f /usr/local/bin/minio ]]; then
        log_warn "MinIO already installed, updating..."
    fi

    wget -q --show-progress "$MINIO_BINARY_URL" -O /usr/local/bin/minio
    chmod +x /usr/local/bin/minio

    log_success "MinIO installed"
}

# ============================================
# Install MC (MinIO Client)
# ============================================
install_mc() {
    log_info "Installing MinIO client (mc)..."

    if [[ -f /usr/local/bin/mc ]]; then
        log_warn "mc already installed, updating..."
    fi

    wget -q --show-progress "$MC_BINARY_URL" -O /usr/local/bin/mc
    chmod +x /usr/local/bin/mc

    log_success "mc installed"
}

# ============================================
# Configure Hosts
# ============================================
configure_hosts() {
    log_info "Configuring /etc/hosts..."

    # Add this node's entry
    if ! grep -q "minio${NODE_NUMBER}" /etc/hosts; then
        echo "${PRIVATE_IP} minio${NODE_NUMBER}" >> /etc/hosts
        log_success "Added minio${NODE_NUMBER} to /etc/hosts"
    else
        log_warn "minio${NODE_NUMBER} already in /etc/hosts"
    fi

    echo ""
    echo "=========================================="
    echo -e "${YELLOW}IMPORTANT: Add other nodes to /etc/hosts${NC}"
    echo "=========================================="
    echo ""
    echo "Add these entries on ALL nodes:"
    echo ""
    for i in $(seq 1 $TOTAL_NODES); do
        if [[ $i -eq $NODE_NUMBER ]]; then
            echo "  ${PRIVATE_IP} minio${i}  (this node)"
        else
            echo "  <ip-of-node-${i}> minio${i}"
        fi
    done
    echo ""
}

# ============================================
# Create Environment File
# ============================================
create_env_file() {
    log_info "Creating MinIO environment file..."

    # Build volumes string: http://minio{1...N}:9000/mnt/disk{1...M}/minio
    local volumes="http://minio{1...${TOTAL_NODES}}:9000${MOUNT_PREFIX}{1...${DRIVE_COUNT}}/minio"

    cat > /etc/default/minio << EOF
# MinIO Environment Configuration
# Generated by install-multi-drive.sh for node ${NODE_NUMBER}

# Credentials
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}

# Distributed cluster volumes
# ${TOTAL_NODES} nodes x ${DRIVE_COUNT} drives = $((TOTAL_NODES * DRIVE_COUNT)) total drives
MINIO_VOLUMES="${volumes}"

# Server URL (this node)
MINIO_SERVER_URL="http://minio${NODE_NUMBER}:9000"

# Console settings
MINIO_CONSOLE_ADDRESS=":9001"
MINIO_BROWSER_REDIRECT_URL="http://minio${NODE_NUMBER}:9001"

# Site settings
MINIO_SITE_REGION=${MINIO_REGION}
MINIO_SITE_NAME=minio-cluster

# Performance tuning for video storage
MINIO_API_REQUESTS_MAX=10000
MINIO_API_REQUESTS_DEADLINE=2m

# Metrics (optional - set to public for Prometheus)
# MINIO_PROMETHEUS_AUTH_TYPE=public
EOF

    chmod 600 /etc/default/minio
    log_success "Environment file created at /etc/default/minio"
}

# ============================================
# Create Systemd Service
# ============================================
create_systemd_service() {
    log_info "Creating systemd service..."

    cat > /etc/systemd/system/minio.service << 'EOF'
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
ExecStart=/usr/local/bin/minio server $MINIO_VOLUMES --console-address $MINIO_CONSOLE_ADDRESS

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
ReadWritePaths=/mnt/disk1 /mnt/disk2 /mnt/disk3 /mnt/disk4

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
    local raw_tb=$((TOTAL_NODES * DRIVE_COUNT * 10))  # assuming 10TB drives
    local usable_tb=$((raw_tb / 2))

    echo ""
    echo "============================================"
    echo -e "${GREEN}MinIO Node ${NODE_NUMBER} Installation Complete!${NC}"
    echo "============================================"
    echo ""
    echo "Cluster Configuration:"
    echo "  Nodes:           ${TOTAL_NODES}"
    echo "  Drives per node: ${DRIVE_COUNT}"
    echo "  Total drives:    ${total_drives}"
    echo "  Erasure Coding:  EC:${parity}"
    echo "  Raw capacity:    ~${raw_tb}TB"
    echo "  Usable:          ~${usable_tb}TB"
    echo "  Fault tolerance: ${parity} drives (or $((TOTAL_NODES/2)) full nodes)"
    echo ""
    echo "This Node:"
    echo "  Node number:     ${NODE_NUMBER}"
    echo "  Private IP:      ${PRIVATE_IP}"
    echo "  Hostname:        minio${NODE_NUMBER}"
    echo "  Drives:          ${MOUNT_PREFIX}1 - ${MOUNT_PREFIX}${DRIVE_COUNT}"
    echo ""
    echo "URLs (after cluster is running):"
    echo "  S3 API:          http://minio${NODE_NUMBER}:9000"
    echo "  Console:         http://minio${NODE_NUMBER}:9001"
    echo ""
    echo "Credentials:"
    echo "  Username:        ${MINIO_ROOT_USER}"
    echo "  Password:        ${MINIO_ROOT_PASSWORD}"
    echo ""
    echo "Next Steps:"
    echo "  1. Run this script on ALL other nodes"
    echo "  2. Update /etc/hosts on ALL nodes with all IP mappings"
    echo "  3. Start MinIO: systemctl start minio"
    echo "  4. Check status: systemctl status minio"
    echo "  5. Setup mc: mc alias set myminio http://minio1:9000 ${MINIO_ROOT_USER} '${MINIO_ROOT_PASSWORD}'"
    echo ""
}

# ============================================
# Main
# ============================================
main() {
    echo ""
    echo "=========================================="
    echo "  MinIO Multi-Drive Installation Script"
    echo "  For ${TOTAL_NODES} nodes with ${DRIVE_COUNT} drives each"
    echo "=========================================="
    echo ""

    parse_args "$@"
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
