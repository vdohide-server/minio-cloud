#!/bin/bash
#
# Add New Nodes to MinIO Cluster
# 
# ใช้สำหรับขยาย cluster โดยเพิ่ม Server Pool ใหม่
#
# Usage:
#   ./add-node.sh --current 4 --new-start 5 --new-end 8
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# ============================
# Configuration
# ============================
CURRENT_NODES=""
NEW_START=""
NEW_END=""

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --current)
            CURRENT_NODES="$2"
            shift 2
            ;;
        --new-start)
            NEW_START="$2"
            shift 2
            ;;
        --new-end)
            NEW_END="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

[[ -z "$CURRENT_NODES" ]] && error "Missing --current (current node count)"
[[ -z "$NEW_START" ]] && error "Missing --new-start (first new node number)"
[[ -z "$NEW_END" ]] && error "Missing --new-end (last new node number)"

# ============================
# Generate New Config
# ============================
echo ""
echo "=========================================="
echo "MinIO Cluster Expansion"
echo "=========================================="
echo ""
echo "Current nodes: 1 - ${CURRENT_NODES}"
echo "New nodes: ${NEW_START} - ${NEW_END}"
echo ""

# Calculate new volume string
# Pool 1: existing nodes
# Pool 2: new nodes
POOL1="http://minio{1...${CURRENT_NODES}}/data"
POOL2="http://minio{${NEW_START}...${NEW_END}}/data"
NEW_VOLUMES="${POOL1} ${POOL2}"

log "New MINIO_VOLUMES configuration:"
echo ""
echo "  ${NEW_VOLUMES}"
echo ""

# ============================
# Create Updated Config
# ============================
BACKUP_FILE="/etc/default/minio.backup.$(date +%Y%m%d%H%M%S)"
NEW_CONFIG="/etc/default/minio.new"

log "Backing up current config to ${BACKUP_FILE}"
cp /etc/default/minio "$BACKUP_FILE"

# Read current config and update volumes
source /etc/default/minio

cat > "$NEW_CONFIG" << EOF
# MinIO Distributed Configuration
# EXPANDED: $(date)
# Pools: 1-${CURRENT_NODES} + ${NEW_START}-${NEW_END}

# Credentials (unchanged)
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}

# EXPANDED Distributed volumes
# Pool 1: Original nodes (1-${CURRENT_NODES})
# Pool 2: New nodes (${NEW_START}-${NEW_END})
MINIO_VOLUMES="${NEW_VOLUMES}"

# Console
MINIO_OPTS="--console-address :9001"

# Site
MINIO_SITE_REGION=${MINIO_SITE_REGION:-cloud}
MINIO_SITE_NAME=${MINIO_SITE_NAME:-minio-cluster}

# Prometheus
MINIO_PROMETHEUS_AUTH_TYPE=public
EOF

chmod 600 "$NEW_CONFIG"

# ============================
# Generate Expansion Steps
# ============================
echo ""
echo "=========================================="
echo -e "${YELLOW}EXPANSION STEPS${NC}"
echo "=========================================="
echo ""
echo "Step 1: Prepare new nodes (${NEW_START}-${NEW_END})"
echo "   Run on each new node:"
echo ""
for i in $(seq $NEW_START $NEW_END); do
    echo "   # Node ${i}:"
    echo "   sudo ./install.sh --node ${i} --total ${NEW_END} --ip <NODE_${i}_IP>"
    echo ""
done
echo ""
echo "Step 2: Update /etc/hosts on ALL nodes"
echo "   Add entries for minio${NEW_START} - minio${NEW_END}"
echo ""
echo "Step 3: Stop MinIO on ALL existing nodes"
echo "   for node in minio{1..${CURRENT_NODES}}; do"
echo "     ssh \$node 'sudo systemctl stop minio'"
echo "   done"
echo ""
echo "Step 4: Copy new config to ALL nodes (old + new)"
echo "   for node in minio{1..${NEW_END}}; do"
echo "     scp ${NEW_CONFIG} \$node:/etc/default/minio"
echo "   done"
echo ""
echo "Step 5: Start MinIO on ALL nodes"
echo "   for node in minio{1..${NEW_END}}; do"
echo "     ssh \$node 'sudo systemctl start minio'"
echo "   done"
echo ""
echo "Step 6: Verify cluster"
echo "   mc admin info mycluster"
echo ""
echo "=========================================="
echo ""
echo "New config saved to: ${NEW_CONFIG}"
echo "Backup saved to: ${BACKUP_FILE}"
echo ""
