#!/bin/bash
#
# Update MinIO Node Configuration
#
# อัพเดท config บน node ตัวเอง (ไม่ต้องใช้ SSH)
# - อัพเดท /etc/hosts
# - อัพเดท /etc/default/minio
# - Restart MinIO service
#
# Usage:
#   sudo ./update-nodes.sh                 # อัพเดท node นี้
#   sudo ./update-nodes.sh --dry-run       # แสดงสิ่งที่จะทำ ไม่รันจริง
#   sudo ./update-nodes.sh --restart       # อัพเดทและ restart MinIO
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/pools.conf"
MINIO_ENV="${SCRIPT_DIR}/config/minio.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Options
DRY_RUN=false
DO_RESTART=false
STOP_ONLY=false
START_ONLY=false

show_help() {
    echo "Usage: sudo ./update-nodes.sh [options]"
    echo ""
    echo "Update this MinIO node with pool configuration from pools.conf"
    echo ""
    echo "Options:"
    echo "  --dry-run       Show what would be done without executing"
    echo "  --restart       Update config and restart MinIO"
    echo "  --stop          Stop MinIO"
    echo "  --start         Start MinIO"
    echo "  --help, -h      Show this help"
    echo ""
    echo "Files used:"
    echo "  config/pools.conf    Pool and node IP definitions"
    echo ""
    exit 0
}

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --restart)
            DO_RESTART=true
            shift
            ;;
        --stop)
            STOP_ONLY=true
            shift
            ;;
        --start)
            START_ONLY=true
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Check config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    error "Config file not found: $CONFIG_FILE"
fi

# Source config
source "$CONFIG_FILE"

# Source credentials
if [[ -f "$MINIO_ENV" ]]; then
    source "$MINIO_ENV"
fi

# ============================
# Parse Pools from Config
# ============================
declare -a POOLS
declare -a ALL_NODES
TOTAL_NODES=0

# Find all pools
POOL_NUM=1
while true; do
    START_VAR="POOL${POOL_NUM}_START"
    END_VAR="POOL${POOL_NUM}_END"
    DISKS_VAR="POOL${POOL_NUM}_DISKS"
    PATH_VAR="POOL${POOL_NUM}_PATH"
    
    if [[ -z "${!START_VAR}" ]]; then
        break
    fi
    
    START=${!START_VAR}
    END=${!END_VAR}
    DISKS=${!DISKS_VAR:-1}
    DATA_PATH=${!PATH_VAR:-/mnt/minio-data}
    
    # Generate pool volume string
    if [[ $DISKS -eq 1 ]]; then
        POOL_STR="http://minio{${START}...${END}}:9000${DATA_PATH}"
    else
        POOL_STR="http://minio{${START}...${END}}:9000${DATA_PATH}/disk{1...${DISKS}}"
    fi
    
    POOLS+=("$POOL_STR")
    
    # Add nodes to list
    for i in $(seq $START $END); do
        ALL_NODES+=($i)
        if [[ $i -gt $TOTAL_NODES ]]; then
            TOTAL_NODES=$i
        fi
    done
    
    POOL_NUM=$((POOL_NUM + 1))
done

if [[ ${#POOLS[@]} -eq 0 ]]; then
    error "No pools defined in $CONFIG_FILE"
fi

# Generate MINIO_VOLUMES string
MINIO_VOLUMES=""
for pool in "${POOLS[@]}"; do
    if [[ -z "$MINIO_VOLUMES" ]]; then
        MINIO_VOLUMES="$pool"
    else
        MINIO_VOLUMES="$MINIO_VOLUMES $pool"
    fi
done

# ============================
# Generate /etc/hosts entries
# ============================
generate_hosts() {
    echo "# MinIO Cluster Nodes (auto-generated)"
    for i in $(seq 1 $TOTAL_NODES); do
        IP_VAR="NODE${i}_IP"
        if [[ -n "${!IP_VAR}" ]]; then
            echo "${!IP_VAR} minio${i}"
        fi
    done
}

# ============================
# Generate /etc/default/minio
# ============================
generate_minio_config() {
    cat << EOF
# MinIO Distributed Configuration
# Generated: $(date)
# Pools: ${#POOLS[@]}

# Credentials
MINIO_ROOT_USER=${MINIO_ROOT_USER:-admin}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:-changeme123}

# Distributed volumes
EOF

    POOL_NUM=1
    for pool in "${POOLS[@]}"; do
        echo "# Pool ${POOL_NUM}: ${pool}"
        POOL_NUM=$((POOL_NUM + 1))
    done

    cat << EOF
MINIO_VOLUMES="${MINIO_VOLUMES}"

# Console
MINIO_OPTS="--console-address :9001"

# Site
MINIO_SITE_REGION=${MINIO_SITE_REGION:-cloud}
MINIO_SITE_NAME=${MINIO_SITE_NAME:-minio-cluster}

# Prometheus
MINIO_PROMETHEUS_AUTH_TYPE=public
EOF
}

# ============================
# Display Summary
# ============================
echo ""
echo "=========================================="
echo -e "${BLUE}MinIO Cluster Update${NC}"
echo "=========================================="
echo ""
echo -e "${YELLOW}Pools (${#POOLS[@]} total):${NC}"
POOL_NUM=1
for pool in "${POOLS[@]}"; do
    echo "  Pool ${POOL_NUM}: ${pool}"
    POOL_NUM=$((POOL_NUM + 1))
done
echo ""
echo -e "${YELLOW}Nodes (${#ALL_NODES[@]} total):${NC}"
for i in "${ALL_NODES[@]}"; do
    IP_VAR="NODE${i}_IP"
    echo "  minio${i}: ${!IP_VAR}"
done
echo ""

# ============================
# Stop Only Mode
# ============================
if [[ "$STOP_ONLY" == true ]]; then
    echo -e "${YELLOW}Stopping MinIO...${NC}"
    if [[ "$DRY_RUN" == false ]]; then
        systemctl stop minio || warn "Failed to stop minio"
    fi
    log "MinIO stopped."
    exit 0
fi

# ============================
# Start Only Mode
# ============================
if [[ "$START_ONLY" == true ]]; then
    echo -e "${YELLOW}Starting MinIO...${NC}"
    if [[ "$DRY_RUN" == false ]]; then
        systemctl start minio || warn "Failed to start minio"
    fi
    log "MinIO started."
    exit 0
fi

# ============================
# Show Generated Files
# ============================
echo -e "${YELLOW}/etc/hosts entries:${NC}"
echo "---"
generate_hosts
echo "---"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}/etc/default/minio:${NC}"
    echo "---"
    generate_minio_config
    echo "---"
    echo ""
    echo -e "${YELLOW}[DRY-RUN] No changes made.${NC}"
    exit 0
fi

# ============================
# Update This Node
# ============================
echo -e "${GREEN}Updating this node...${NC}"
echo ""

# Update /etc/hosts
log "Updating /etc/hosts..."
if [[ "$DRY_RUN" == false ]]; then
    # Remove old minio entries
    sed -i '/^.*minio[0-9]*/d' /etc/hosts
    # Add new entries
    generate_hosts >> /etc/hosts
fi

# Update /etc/default/minio
log "Updating /etc/default/minio..."
if [[ "$DRY_RUN" == false ]]; then
    generate_minio_config > /etc/default/minio
    chmod 600 /etc/default/minio
fi

log "Node updated!"
echo ""

# ============================
# Restart if requested
# ============================
if [[ "$DO_RESTART" == true ]]; then
    echo -e "${YELLOW}Restarting MinIO...${NC}"
    
    if [[ "$DRY_RUN" == false ]]; then
        systemctl restart minio || warn "Failed to restart minio"
    fi
    
    log "MinIO restarted!"
    echo ""
    echo "Verify cluster:"
    echo "  mc admin info myminio"
else
    echo -e "${YELLOW}Next steps:${NC}"
    echo ""
    echo "1. Restart MinIO:"
    echo "   sudo systemctl restart minio"
    echo ""
    echo "2. Or use:"
    echo "   sudo ./update-nodes.sh --restart"
    echo ""
    echo "3. Verify cluster:"
    echo "   mc admin info myminio"
    echo ""
    echo -e "${YELLOW}Note: Run this script on ALL nodes!${NC}"
fi

echo ""
