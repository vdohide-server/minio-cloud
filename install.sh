#!/bin/bash
#
# MinIO Cloud Installation Script
# For Distributed Cluster
#
# Usage:
#   sudo ./install.sh --node 1 --ip 10.0.0.1
#   sudo ./install.sh --node 2 --ip 10.0.0.2
#

set -e

# ============================
# Default Configuration
# ============================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/pools.conf"

NODE_NUM=""
NODE_IP=""
MINIO_USER="minio-user"
MINIO_PORT=9000
CONSOLE_PORT=9001

# ============================
# Colors
# ============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# ============================
# Parse Arguments
# ============================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --node)
                NODE_NUM="$2"
                shift 2
                ;;
            --ip)
                NODE_IP="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    # Validate required args
    if [[ -z "$NODE_NUM" ]]; then
        error "Missing --node"
    fi
    if [[ -z "$NODE_IP" ]]; then
        error "Missing --ip"
    fi
}

show_help() {
    cat << EOF
MinIO Cloud Installation Script

Usage:
  sudo ./install.sh --node <num> --ip <private_ip>

Options:
  --node       Node number (1, 2, 3, ...) - must match pools.conf
  --ip         Private IP of this node
  --help       Show this help

Example:
  sudo ./install.sh --node 1 --ip 10.0.0.3
  sudo ./install.sh --node 2 --ip 10.0.0.5

Note:
  Pool configuration is read from config/pools.conf
EOF
}

# ============================
# Check Root
# ============================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# ============================
# Install Dependencies
# ============================
install_deps() {
    log "Installing dependencies..."

    apt-get update -qq
    apt-get install -y -qq curl wget ca-certificates xfsprogs

    log "Dependencies installed"
}

# ============================
# Install MinIO
# ============================
install_minio() {
    log "Installing MinIO..."

    # Download latest MinIO
    MINIO_URL="https://dl.min.io/server/minio/release/linux-amd64/minio"

    if [[ -f /usr/local/bin/minio ]]; then
        warn "MinIO binary already exists, updating..."
    fi

    wget -q "$MINIO_URL" -O /usr/local/bin/minio
    chmod +x /usr/local/bin/minio

    # Verify installation
    /usr/local/bin/minio --version

    log "MinIO installed: $(/usr/local/bin/minio --version | head -1)"
}

# ============================
# Install MinIO Client (mc)
# ============================
install_mc() {
    log "Installing MinIO Client (mc)..."

    MC_URL="https://dl.min.io/client/mc/release/linux-amd64/mc"

    wget -q "$MC_URL" -O /usr/local/bin/mc
    chmod +x /usr/local/bin/mc

    log "MinIO Client installed"
}

# ============================
# Setup Data Directory
# ============================
setup_data_dir() {
    # Load pools.conf to get data path
    source "$CONFIG_FILE"
    
    # Find which pool this node belongs to
    local POOL_NUM=1
    local DATA_PATH="/mnt/minio-data"
    local DISKS=1
    
    while true; do
        local START_VAR="POOL${POOL_NUM}_START"
        local END_VAR="POOL${POOL_NUM}_END"
        local PATH_VAR="POOL${POOL_NUM}_PATH"
        local DISKS_VAR="POOL${POOL_NUM}_DISKS"
        
        if [[ -z "${!START_VAR}" ]]; then
            break
        fi
        
        if [[ $NODE_NUM -ge ${!START_VAR} && $NODE_NUM -le ${!END_VAR} ]]; then
            DATA_PATH="${!PATH_VAR:-/mnt/minio-data}"
            DISKS="${!DISKS_VAR:-1}"
            break
        fi
        
        POOL_NUM=$((POOL_NUM + 1))
    done
    
    log "Setting up data directory: ${DATA_PATH}..."

    # Create directories based on disk count
    if [[ $DISKS -eq 1 ]]; then
        mkdir -p "$DATA_PATH"
        chown -R ${MINIO_USER}:${MINIO_USER} "$DATA_PATH" 2>/dev/null || true
    else
        for i in $(seq 1 $DISKS); do
            mkdir -p "${DATA_PATH}/disk${i}"
            chown -R ${MINIO_USER}:${MINIO_USER} "${DATA_PATH}/disk${i}" 2>/dev/null || true
        done
    fi

    log "Data directory ready (${DISKS} disk(s))"
}

# ============================
# Create MinIO User
# ============================
create_user() {
    log "Creating MinIO user..."

    if id "$MINIO_USER" &>/dev/null; then
        log "User ${MINIO_USER} already exists"
    else
        groupadd -r "$MINIO_USER"
        useradd -M -r -g "$MINIO_USER" "$MINIO_USER"
        log "User ${MINIO_USER} created"
    fi
}

# ============================
# Generate Hosts Entries
# ============================
generate_hosts() {
    log "Generating /etc/hosts entries..."

    # Backup
    cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d%H%M%S)

    # Read IP mappings from pools.conf
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        
        # Add entries from NODE*_IP variables
        for i in $(seq 1 20); do
            IP_VAR="NODE${i}_IP"
            if [[ -n "${!IP_VAR}" ]]; then
                if ! grep -q "minio${i}" /etc/hosts; then
                    echo "${!IP_VAR} minio${i}" >> /etc/hosts
                    log "Added minio${i} (${!IP_VAR}) to /etc/hosts"
                fi
            fi
        done
    else
        error "Config file not found: $CONFIG_FILE"
    fi

    log "Hosts file configured"
}

# ============================
# Create MinIO Config
# ============================
create_config() {
    log "Creating MinIO configuration..."

    # Load from pools.conf
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Config file not found: $CONFIG_FILE"
    fi
    source "$CONFIG_FILE"

    # ============================
    # Parse Pools from Config (same logic as update-nodes.sh)
    # ============================
    declare -a POOLS
    local POOL_NUM=1
    
    while true; do
        local START_VAR="POOL${POOL_NUM}_START"
        local END_VAR="POOL${POOL_NUM}_END"
        local DISKS_VAR="POOL${POOL_NUM}_DISKS"
        local PATH_VAR="POOL${POOL_NUM}_PATH"
        
        if [[ -z "${!START_VAR}" ]]; then
            break
        fi
        
        local START=${!START_VAR}
        local END=${!END_VAR}
        local DISKS=${!DISKS_VAR:-1}
        local POOL_PATH=${!PATH_VAR:-/mnt/minio-data}
        
        # Generate pool volume string
        if [[ $DISKS -eq 1 ]]; then
            POOLS+=("http://minio{${START}...${END}}:9000${POOL_PATH}")
        else
            POOLS+=("http://minio{${START}...${END}}:9000${POOL_PATH}/disk{1...${DISKS}}")
        fi
        
        POOL_NUM=$((POOL_NUM + 1))
    done

    if [[ ${#POOLS[@]} -eq 0 ]]; then
        error "No pools defined in $CONFIG_FILE"
    fi

    # Join pools into MINIO_VOLUMES string
    local MINIO_VOLUMES=""
    for pool in "${POOLS[@]}"; do
        if [[ -z "$MINIO_VOLUMES" ]]; then
            MINIO_VOLUMES="$pool"
        else
            MINIO_VOLUMES="$MINIO_VOLUMES $pool"
        fi
    done

    # Use credentials from pools.conf
    MINIO_ROOT_USER="${MINIO_ROOT_USER:-admin}"
    MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-changeme123}"
    MINIO_SITE_REGION="${MINIO_SITE_REGION:-cloud}"
    MINIO_SITE_NAME="${MINIO_SITE_NAME:-minio-cluster}"

    # Create systemd environment file
    cat > /etc/default/minio << EOF
# MinIO Distributed Configuration
# Node: ${NODE_NUM}
# Pools: ${#POOLS[@]}
# Generated: $(date)

# Credentials (same on all nodes!)
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}

# Distributed volumes
MINIO_VOLUMES="${MINIO_VOLUMES}"

# Console
MINIO_OPTS="--console-address :${CONSOLE_PORT}"

# Site
MINIO_SITE_REGION=${MINIO_SITE_REGION}
MINIO_SITE_NAME=${MINIO_SITE_NAME}

# Prometheus (optional)
MINIO_PROMETHEUS_AUTH_TYPE=public
EOF

    chmod 600 /etc/default/minio

    log "Configuration created at /etc/default/minio"
    log "Pools: ${#POOLS[@]}, Volumes: ${MINIO_VOLUMES}"
}

# ============================
# Create Systemd Service
# ============================
create_service() {
    log "Creating systemd service..."

    cat > /etc/systemd/system/minio.service << 'EOF'
[Unit]
Description=MinIO Object Storage
Documentation=https://min.io/docs
Wants=network-online.target
After=network-online.target
AssertFileIsExecutable=/usr/local/bin/minio

[Service]
Type=notify
WorkingDirectory=/usr/local

User=minio-user
Group=minio-user

EnvironmentFile=/etc/default/minio
ExecStart=/usr/local/bin/minio server $MINIO_OPTS $MINIO_VOLUMES

# Restart policy
Restart=on-failure
RestartSec=5

# Limits
LimitNOFILE=1048576
LimitNPROC=1048576
TasksMax=infinity

# Security
ProtectSystem=full
ProtectHome=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable minio

    log "Systemd service created and enabled"
}

# ============================
# System Tuning
# ============================
tune_system() {
    log "Applying system tuning..."

    # Sysctl
    cat > /etc/sysctl.d/99-minio.conf << 'EOF'
# MinIO tuning
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535
vm.swappiness = 1
vm.dirty_ratio = 80
vm.dirty_background_ratio = 5
fs.file-max = 1048576
EOF
    sysctl -p /etc/sysctl.d/99-minio.conf 2>/dev/null || true

    # Limits
    cat > /etc/security/limits.d/minio.conf << 'EOF'
minio-user soft nofile 1048576
minio-user hard nofile 1048576
minio-user soft nproc 65535
minio-user hard nproc 65535
EOF

    log "System tuning applied"
}

# ============================
# Setup Firewall
# ============================
setup_firewall() {
    log "Configuring firewall..."

    if command -v ufw &> /dev/null; then
        ufw allow ${MINIO_PORT}/tcp comment 'MinIO API'
        ufw allow ${CONSOLE_PORT}/tcp comment 'MinIO Console'
        log "UFW rules added"
    else
        warn "UFW not installed, skipping firewall setup"
    fi
}

# ============================
# Print Summary
# ============================
print_summary() {
    echo ""
    echo "=========================================="
    echo -e "${GREEN}MinIO Installation Complete!${NC}"
    echo "=========================================="
    echo ""
    echo "Node: minio${NODE_NUM}"
    echo "IP: ${NODE_IP}"
    echo "Config: ${CONFIG_FILE}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo ""
    echo "1. Run this script on ALL other nodes"
    echo ""
    echo "2. Start MinIO on ALL nodes:"
    echo "   sudo systemctl start minio"
    echo ""
    echo "3. Check status:"
    echo "   sudo systemctl status minio"
    echo "   sudo journalctl -u minio -f"
    echo ""
    echo "4. Or use update-nodes.sh to manage all nodes:"
    echo "   ./update-nodes.sh --restart"
    echo ""
    echo "=========================================="
}

# ============================
# Main
# ============================
main() {
    parse_args "$@"

    echo ""
    echo "=========================================="
    echo "MinIO Cloud Installation"
    echo "Node: minio${NODE_NUM}"
    echo "=========================================="
    echo ""

    check_root
    install_deps
    install_minio
    install_mc
    create_user
    setup_data_dir
    generate_hosts
    create_config
    create_service
    tune_system
    setup_firewall
    print_summary
}

main "$@"
