#!/bin/bash
#
# MinIO Console (georgmangold fork) Installation Script
# Provides full-featured admin UI for MinIO
#
# Usage:
#   ./install-console.sh [OPTIONS]
#
# Options:
#   --minio-server URL    MinIO server URL (default: http://minio1:9000)
#   --region REGION       MinIO region (default: cloud)
#   --port PORT           Console port (default: 9090)
#   --help                Show this help
#

set -e

# ============================================
# Configuration
# ============================================
CONSOLE_VERSION="latest"
CONSOLE_BINARY_URL="https://github.com/georgmangold/console/releases/latest/download/console-linux-amd64"
CONSOLE_INSTALL_PATH="/usr/local/bin/console"

# Defaults
MINIO_SERVER="http://minio1:9000"
MINIO_REGION="cloud"
CONSOLE_PORT="9090"

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
            --minio-server)
                if [[ -z "$2" ]]; then
                    log_error "--minio-server requires a URL"
                fi
                MINIO_SERVER="$2"
                shift 2
                ;;
            --region)
                if [[ -z "$2" ]]; then
                    log_error "--region requires a value"
                fi
                MINIO_REGION="$2"
                shift 2
                ;;
            --port)
                if [[ -z "$2" ]]; then
                    log_error "--port requires a value"
                fi
                CONSOLE_PORT="$2"
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
}

show_help() {
    echo "MinIO Console Installation Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --minio-server URL    MinIO server URL (default: http://minio1:9000)"
    echo "  --region REGION       MinIO region (default: cloud)"
    echo "  --port PORT           Console port (default: 9090)"
    echo "  --help                Show this help"
    echo ""
    echo "Example:"
    echo "  $0 --minio-server http://10.0.0.3:9000 --region cloud --port 9090"
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
    
    # Check wget or curl
    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        log_error "wget or curl is required"
    fi
    
    log_success "Prerequisites OK"
}

# ============================================
# Download Console Binary
# ============================================
download_console() {
    log_info "Downloading MinIO Console..."
    
    # Remove old binary if exists
    if [[ -f "$CONSOLE_INSTALL_PATH" ]]; then
        log_warn "Removing existing console binary..."
        rm -f "$CONSOLE_INSTALL_PATH"
    fi
    
    # Download
    if command -v wget &> /dev/null; then
        wget -q --show-progress "$CONSOLE_BINARY_URL" -O "$CONSOLE_INSTALL_PATH"
    else
        curl -L --progress-bar "$CONSOLE_BINARY_URL" -o "$CONSOLE_INSTALL_PATH"
    fi
    
    chmod +x "$CONSOLE_INSTALL_PATH"
    
    log_success "Console downloaded to $CONSOLE_INSTALL_PATH"
}

# ============================================
# Create Console User (in MinIO)
# ============================================
create_console_user() {
    log_info "Checking MinIO console user..."
    
    # Check if mc is available
    if ! command -v mc &> /dev/null; then
        log_warn "mc not found - skipping user creation"
        log_warn "You need to create a console user manually:"
        echo "  mc admin user add myminio console YourPassword123!"
        echo "  mc admin policy attach myminio consoleAdmin --user=console"
        return
    fi
    
    # Check if myminio alias exists
    if ! mc alias list | grep -q "myminio"; then
        log_warn "mc alias 'myminio' not found - skipping user creation"
        return
    fi
    
    # Create admin policy if not exists
    log_info "Creating console admin policy..."
    cat > /tmp/console-admin-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": ["admin:*"],
            "Effect": "Allow"
        },
        {
            "Action": ["s3:*"],
            "Effect": "Allow",
            "Resource": ["arn:aws:s3:::*"]
        }
    ]
}
EOF
    
    mc admin policy create myminio consoleAdmin /tmp/console-admin-policy.json 2>/dev/null || true
    rm -f /tmp/console-admin-policy.json
    
    log_success "Console policy ready"
}

# ============================================
# Create Systemd Service
# ============================================
create_systemd_service() {
    log_info "Creating systemd service..."
    
    cat > /etc/systemd/system/minio-console.service << EOF
[Unit]
Description=MinIO Console (georgmangold fork)
Documentation=https://github.com/georgmangold/console
After=network.target minio.service
Wants=minio.service

[Service]
Type=simple
User=root
Group=root

# Environment
Environment="CONSOLE_MINIO_SERVER=${MINIO_SERVER}"
Environment="CONSOLE_MINIO_REGION=${MINIO_REGION}"
Environment="CONSOLE_PORT=${CONSOLE_PORT}"

# Start command
ExecStart=${CONSOLE_INSTALL_PATH} server --port ${CONSOLE_PORT}

# Restart policy
Restart=always
RestartSec=5
TimeoutStopSec=30

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=minio-console

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    
    log_success "Systemd service created"
}

# ============================================
# Start Console Service
# ============================================
start_console() {
    log_info "Starting MinIO Console..."
    
    systemctl enable minio-console
    systemctl start minio-console
    
    sleep 2
    
    if systemctl is-active --quiet minio-console; then
        log_success "MinIO Console is running"
    else
        log_error "Failed to start MinIO Console. Check: journalctl -u minio-console"
    fi
}

# ============================================
# Print Summary
# ============================================
print_summary() {
    local PUBLIC_IP
    PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "<your-ip>")
    
    echo ""
    echo "============================================"
    echo -e "${GREEN}MinIO Console Installation Complete!${NC}"
    echo "============================================"
    echo ""
    echo "Console URL:     http://${PUBLIC_IP}:${CONSOLE_PORT}"
    echo "MinIO Server:    ${MINIO_SERVER}"
    echo "Region:          ${MINIO_REGION}"
    echo ""
    echo "Login credentials:"
    echo "  Use your MinIO user credentials"
    echo "  (e.g., console / Console123!)"
    echo ""
    echo "Useful commands:"
    echo "  systemctl status minio-console   # Check status"
    echo "  systemctl restart minio-console  # Restart"
    echo "  journalctl -u minio-console -f   # View logs"
    echo ""
    echo "To create a console user:"
    echo "  mc admin user add myminio console YourPassword!"
    echo "  mc admin policy attach myminio consoleAdmin --user=console"
    echo ""
}

# ============================================
# Main
# ============================================
main() {
    echo ""
    echo "=========================================="
    echo "  MinIO Console Installer"
    echo "  (georgmangold fork with full features)"
    echo "=========================================="
    echo ""
    
    parse_args "$@"
    check_prerequisites
    download_console
    create_console_user
    create_systemd_service
    start_console
    print_summary
}

main "$@"
