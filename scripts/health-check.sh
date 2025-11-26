#!/bin/bash
#
# MinIO Health Check Script
# ตรวจสอบสถานะของ MinIO Cluster
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/pools.conf"

# Load config
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Configuration
MINIO_ALIAS="${1:-mycluster}"
ALERT_EMAIL="${ALERT_EMAIL:-}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=========================================="
echo "MinIO Health Check"
echo "Timestamp: $(date)"
echo "=========================================="
echo ""

# ============================
# Check MinIO Service
# ============================
echo "1. Checking MinIO service..."

if systemctl is-active --quiet minio; then
    echo -e "   ${GREEN}✓${NC} MinIO service is running"
else
    echo -e "   ${RED}✗${NC} MinIO service is NOT running!"
    echo "   Try: sudo systemctl start minio"
    exit 1
fi

# ============================
# Check Local Health Endpoint
# ============================
echo ""
echo "2. Checking local health..."

if curl -sf http://localhost:9000/minio/health/live > /dev/null 2>&1; then
    echo -e "   ${GREEN}✓${NC} Local health check passed"
else
    echo -e "   ${RED}✗${NC} Local health check FAILED!"
fi

# ============================
# Check Cluster Health
# ============================
echo ""
echo "3. Checking cluster health..."

if command -v mc &> /dev/null; then
    CLUSTER_HEALTH=$(curl -sf http://localhost:9000/minio/health/cluster 2>/dev/null)
    if [[ "$CLUSTER_HEALTH" == *"healthy"* ]] || [[ $? -eq 0 ]]; then
        echo -e "   ${GREEN}✓${NC} Cluster is healthy"
    else
        echo -e "   ${YELLOW}⚠${NC} Cluster may have issues"
    fi
else
    echo -e "   ${YELLOW}⚠${NC} mc not installed, skipping detailed check"
fi

# ============================
# Check Disk Usage
# ============================
echo ""
echo "4. Checking disk usage..."

DATA_PATH="/mnt/minio-data"
if [[ -d "$DATA_PATH" ]]; then
    USAGE=$(df -h "$DATA_PATH" | tail -1 | awk '{print $5}' | tr -d '%')
    TOTAL=$(df -h "$DATA_PATH" | tail -1 | awk '{print $2}')
    USED=$(df -h "$DATA_PATH" | tail -1 | awk '{print $3}')
    
    if [[ $USAGE -lt 80 ]]; then
        echo -e "   ${GREEN}✓${NC} Disk usage: ${USED}/${TOTAL} (${USAGE}%)"
    elif [[ $USAGE -lt 90 ]]; then
        echo -e "   ${YELLOW}⚠${NC} Disk usage: ${USED}/${TOTAL} (${USAGE}%) - Warning!"
    else
        echo -e "   ${RED}✗${NC} Disk usage: ${USED}/${TOTAL} (${USAGE}%) - Critical!"
    fi
else
    echo -e "   ${YELLOW}⚠${NC} Data path not found: $DATA_PATH"
fi

# ============================
# Check Memory
# ============================
echo ""
echo "5. Checking memory..."

MEM_TOTAL=$(free -h | grep Mem | awk '{print $2}')
MEM_USED=$(free -h | grep Mem | awk '{print $3}')
MEM_PCT=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')

if [[ $MEM_PCT -lt 80 ]]; then
    echo -e "   ${GREEN}✓${NC} Memory: ${MEM_USED}/${MEM_TOTAL} (${MEM_PCT}%)"
else
    echo -e "   ${YELLOW}⚠${NC} Memory: ${MEM_USED}/${MEM_TOTAL} (${MEM_PCT}%) - High!"
fi

# ============================
# Check Network Connectivity
# ============================
echo ""
echo "6. Checking network to other nodes..."

# Check all nodes from pools.conf
for i in $(seq 1 20); do
    IP_VAR="NODE${i}_IP"
    if [[ -n "${!IP_VAR}" ]]; then
        IP="${!IP_VAR}"
        HOST="minio${i}"
        if ping -c 1 -W 2 "$IP" &> /dev/null; then
            echo -e "   ${GREEN}✓${NC} ${HOST} ($IP) - reachable"
        else
            echo -e "   ${RED}✗${NC} ${HOST} ($IP) - NOT reachable!"
        fi
    fi
done

# ============================
# Check Recent Errors
# ============================
echo ""
echo "7. Recent errors (last 10)..."

ERRORS=$(journalctl -u minio --since "1 hour ago" -p err --no-pager 2>/dev/null | tail -5)
if [[ -z "$ERRORS" ]]; then
    echo -e "   ${GREEN}✓${NC} No recent errors"
else
    echo -e "   ${YELLOW}⚠${NC} Recent errors found:"
    echo "$ERRORS" | sed 's/^/   /'
fi

# ============================
# Summary
# ============================
echo ""
echo "=========================================="
echo "Health check complete"
echo "=========================================="
echo ""
