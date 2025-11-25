#!/bin/bash
#
# MinIO Cloud Installation Script
# For Distributed Cluster (1 disk per node)
#
# Usage:
#   sudo ./install.sh --node 1 --total 4 --ip 10.0.0.1
#   sudo ./install.sh --node 2 --total 4 --ip 10.0.0.2
#

set -e

# ============================
# Default Configuration
# ============================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/minio.env"

NODE_NUM=""
TOTAL_NODES=""
NODE_IP=""
DATA_PATH="/mnt/minio-data"
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
            --total)
                TOTAL_NODES="$2"
                shift 2
                ;;
            --ip)
                NODE_IP="$2"
                shift 2
                ;;
            --data-path)
                DATA_PATH="$2"
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
    if [[ -z "$TOTAL_NODES" ]]; then
        error "Missing --total"
    fi
    if [[ -z "$NODE_IP" ]]; then
        error "Missing --ip"
    fi

    # Validate values
    if [[ "$TOTAL_NODES" -lt 4 ]]; then
        error "Minimum 4 nodes required"
    fi
    if [[ "$NODE_NUM" -gt "$TOTAL_NODES" ]]; then
        error "Node number cannot exceed total nodes"
    fi
}

show_help() {
    cat << EOF
MinIO Cloud Installation Script

Usage:
  sudo ./install.sh --node <num> --total <count> --ip <private_ip>

Options:
  --node       Node number (1, 2, 3, ...)
  --total      Total number of nodes in cluster
  --ip         Private IP of this node
  --data-path  Data directory (default: /mnt/minio-data)
  --help       Show this help

Example:
  sudo ./install.sh --node 1 --total 4 --ip 10.0.0.1
  sudo ./install.sh --node 2 --total 4 --ip 10.0.0.2
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
    log "Setting up data directory: ${DATA_PATH}..."

    # Create directory
    mkdir -p "$DATA_PATH"

    # Set permissions
    chown -R ${MINIO_USER}:${MINIO_USER} "$DATA_PATH" 2>/dev/null || true

    log "Data directory ready"
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

    # Set ownership
    chown -R ${MINIO_USER}:${MINIO_USER} "$DATA_PATH"
}

# ============================
# Generate Hosts Entries
# ============================
generate_hosts() {
    log "Generating /etc/hosts entries..."

    # Backup
    cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d%H%M%S)

    # Read IP mappings from config if exists
    if [[ -f "${SCRIPT_DIR}/config/nodes.txt" ]]; then
        while IFS='=' read -r node ip; do
            # Skip comments and empty lines
            [[ "$node" =~ ^#.*$ ]] && continue
            [[ -z "$node" ]] && continue
            if ! grep -q "$node" /etc/hosts; then
                echo "$ip $node" >> /etc/hosts
            fi
        done < "${SCRIPT_DIR}/config/nodes.txt"
    else
        # Generate template
        warn "Creating nodes.txt template. Please edit with actual IPs!"
        cat > "${SCRIPT_DIR}/config/nodes.txt" << EOF
# Format: hostname=ip
# Edit this file with your actual node IPs
minio1=10.0.0.1
minio2=10.0.0.2
minio3=10.0.0.3
minio4=10.0.0.4
EOF
    fi

    log "Hosts file configured"
}

# ============================
# Create MinIO Config
# ============================
create_config() {
    log "Creating MinIO configuration..."

    # Generate volumes string for distributed mode
    # Format: http://minio{1...N}/data
    VOLUMES="http://minio{1...${TOTAL_NODES}}/data"

    # Load credentials from config or use defaults
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        MINIO_ROOT_USER="${MINIO_ROOT_USER:-admin}"
        MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-$(openssl rand -base64 24)}"

        # Save generated password
        mkdir -p "$(dirname "$CONFIG_FILE")"
        cat > "$CONFIG_FILE" << EOF
# MinIO Configuration
# Generated on $(date)

MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}

# Cluster settings
TOTAL_NODES=${TOTAL_NODES}

# Site settings
MINIO_SITE_REGION=cloud
MINIO_SITE_NAME=minio-cluster
EOF
        chmod 600 "$CONFIG_FILE"
        warn "Generated new credentials. Save this file: ${CONFIG_FILE}"
    fi

    # Create systemd environment file
    cat > /etc/default/minio << EOF
# MinIO Distributed Configuration
# Node: ${NODE_NUM} of ${TOTAL_NODES}
# Generated: $(date)

# Credentials (same on all nodes!)
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}

# Distributed volumes: 1 disk per node
MINIO_VOLUMES="${VOLUMES}"

# Console
MINIO_OPTS="--console-address :${CONSOLE_PORT}"

# Site
MINIO_SITE_REGION=cloud
MINIO_SITE_NAME=minio-cluster

# Prometheus (optional)
MINIO_PROMETHEUS_AUTH_TYPE=public
EOF

    chmod 600 /etc/default/minio

    log "Configuration created at /etc/default/minio"
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
    echo "Node: ${NODE_NUM} of ${TOTAL_NODES}"
    echo "IP: ${NODE_IP}"
    echo "Data Path: ${DATA_PATH}"
    echo ""
    echo "Credentials saved in: ${CONFIG_FILE}"
    echo ""
    echo -e "${YELLOW}IMPORTANT: Next Steps${NC}"
    echo ""
    echo "1. Edit /etc/hosts on ALL nodes:"
    echo "   Add entries for minio1, minio2, minio3, minio4"
    echo ""
    echo "2. Copy ${CONFIG_FILE} to all nodes"
    echo "   (credentials must be identical)"
    echo ""
    echo "3. Run this script on other nodes"
    echo ""
    echo "4. Start MinIO on ALL nodes simultaneously:"
    echo "   sudo systemctl start minio"
    echo ""
    echo "5. Check status:"
    echo "   sudo systemctl status minio"
    echo "   sudo journalctl -u minio -f"
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
    echo "Node: ${NODE_NUM} of ${TOTAL_NODES}"
    echo "=========================================="
    echo ""

    check_root
    install_deps
    install_minio
    install_mc
    setup_data_dir
    create_user
    generate_hosts
    create_config
    create_service
    tune_system
    setup_firewall
    print_summary
}

main "$@"
