#!/bin/bash
#
# K3s Pi Cluster Observability - Uninstall Script
#
# This script removes the monitoring stack and optionally cleans up storage.

set -e

# Change to project root (parent of scripts directory)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$PROJECT_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="monitoring"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  K3s Pi Cluster Observability - Uninstall${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Ask for confirmation
read -p "This will remove all monitoring components. Continue? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo -e "${BLUE}[1/3] Removing monitoring components...${NC}"
kubectl delete -f manifests/observability/ --recursive --ignore-not-found=true
echo -e "${GREEN}✓${NC} Components removed"
echo ""

echo -e "${BLUE}[2/3] Removing namespace...${NC}"
kubectl delete namespace $NAMESPACE --ignore-not-found=true --timeout=60s
echo -e "${GREEN}✓${NC} Namespace removed"
echo ""

# Ask about storage
echo -e "${BLUE}[3/3] Storage cleanup${NC}"
read -p "Do you want to delete persistent data? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}⚠${NC} Deleting persistent storage..."
    sudo rm -rf /mnt/prometheus-data /mnt/grafana-data
    echo -e "${GREEN}✓${NC} Storage deleted"
else
    echo -e "${BLUE}ℹ${NC} Storage preserved at:"
    echo "   /mnt/prometheus-data"
    echo "   /mnt/grafana-data"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✓ Uninstall Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
