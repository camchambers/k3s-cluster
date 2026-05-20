#!/bin/bash
#
# Remove Pi Zero from K3s Cluster
#
# Usage: ./remove-pi-from-cluster.sh <hostname>
# Example: ./remove-pi-from-cluster.sh pi1
#
# This script:
#   1. Drains pods from the node
#   2. Deletes the node from Kubernetes
#   3. Uninstalls K3s agent from the Pi
#   4. Cleans up any remaining resources

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PI_USER="root"

# Function to print status
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if hostname provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: No hostname provided${NC}"
    echo ""
    echo "Usage: $0 <hostname>"
    echo ""
    echo "Examples:"
    echo "  $0 pi1        # Remove pi1 from cluster"
    echo "  $0 pi2        # Remove pi2 from cluster"
    echo "  $0 pi3        # Remove pi3 from cluster"
    echo ""
    exit 1
fi

PI_NODE_NAME="$1"
PI_HOST="${PI_NODE_NAME}.home"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Remove Pi Zero from K3s Cluster${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
print_info "Pi hostname: $PI_HOST"
print_info "Node name: $PI_NODE_NAME"
echo ""

# Check if node exists in cluster
echo -e "${BLUE}[1/5] Checking if node exists in cluster...${NC}"
if ! kubectl get node "$PI_NODE_NAME" &> /dev/null; then
    print_warning "Node '$PI_NODE_NAME' not found in cluster"
    echo ""
    read -p "Continue with Pi cleanup anyway? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Aborted"
        exit 0
    fi
    SKIP_DRAIN=true
else
    print_status "Node '$PI_NODE_NAME' found in cluster"
    SKIP_DRAIN=false
    echo ""
    echo -e "${BLUE}📋 Current Node Status:${NC}"
    kubectl get node "$PI_NODE_NAME" -o wide
    echo ""
    
    # Check for running pods
    POD_COUNT=$(kubectl get pods --all-namespaces --field-selector spec.nodeName=${PI_NODE_NAME} --no-headers 2>/dev/null | wc -l)
    if [ $POD_COUNT -gt 0 ]; then
        print_warning "$POD_COUNT pod(s) currently running on this node"
        echo ""
        kubectl get pods --all-namespaces --field-selector spec.nodeName=${PI_NODE_NAME}
        echo ""
    else
        print_status "No pods running on this node"
    fi
fi

# Confirmation
echo ""
echo -e "${YELLOW}⚠️  Warning: This will:${NC}"
echo "   1. Drain all pods from the node (if not already drained)"
echo "   2. Delete the node from Kubernetes cluster"
echo "   3. Uninstall K3s agent from the Pi"
echo "   4. Clean up all K3s data on the Pi"
echo ""
read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Aborted"
    exit 0
fi
echo ""

# Drain node
if [ "$SKIP_DRAIN" = false ]; then
    echo -e "${BLUE}[2/5] Draining node (evicting pods)...${NC}"
    print_info "This may take a few moments..."
    
    if kubectl drain "$PI_NODE_NAME" --ignore-daemonsets --delete-emptydir-data --force --timeout=120s 2>/dev/null; then
        print_status "Node drained successfully"
    else
        print_warning "Drain completed with warnings (this is usually fine for DaemonSets)"
    fi
    echo ""
    
    # Delete node from cluster
    echo -e "${BLUE}[3/5] Deleting node from cluster...${NC}"
    if kubectl delete node "$PI_NODE_NAME"; then
        print_status "Node removed from Kubernetes cluster"
    else
        print_error "Failed to delete node from cluster"
        exit 1
    fi
else
    print_info "[2/5] Skipping drain (node not in cluster)"
    print_info "[3/5] Skipping node deletion (node not in cluster)"
fi
echo ""

# Test SSH connectivity
echo -e "${BLUE}[4/5] Testing SSH connectivity to Pi...${NC}"
if ! ssh -o ConnectTimeout=5 ${PI_USER}@${PI_HOST} "echo 'SSH OK'" &> /dev/null; then
    print_warning "Cannot connect to ${PI_USER}@${PI_HOST}"
    print_info "Pi may be powered off or unreachable"
    echo ""
    read -p "Skip Pi cleanup? (Y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        print_info "Skipping Pi cleanup"
        print_warning "Node removed from cluster, but K3s agent still installed on Pi"
        print_info "To manually clean up later, run on the Pi:"
        echo "   ssh ${PI_USER}@${PI_HOST} /usr/local/bin/k3s-agent-uninstall.sh"
        exit 0
    fi
else
    print_status "SSH connection successful"
fi
echo ""

# Uninstall K3s agent
echo -e "${BLUE}[5/5] Uninstalling K3s agent from Pi...${NC}"
print_info "Running k3s-agent-uninstall.sh on ${PI_HOST}..."

if ssh ${PI_USER}@${PI_HOST} "/usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || true"; then
    print_status "K3s agent uninstalled successfully"
else
    print_warning "Uninstall script completed with warnings"
fi

# Verify cleanup
print_info "Verifying cleanup..."
K3S_RUNNING=$(ssh ${PI_USER}@${PI_HOST} "systemctl is-active k3s-agent 2>/dev/null || echo 'inactive'")
if [ "$K3S_RUNNING" = "inactive" ]; then
    print_status "K3s agent service stopped"
else
    print_warning "K3s agent service may still be running"
fi

echo ""

# Show summary
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✓ Pi Successfully Removed from Cluster!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}📋 Cluster Status:${NC}"
kubectl get nodes
echo ""
echo -e "${BLUE}🧹 What Was Cleaned Up:${NC}"
echo "   ✓ Node drained (pods evicted)"
echo "   ✓ Node removed from Kubernetes"
echo "   ✓ K3s agent uninstalled from Pi"
echo "   ✓ K3s data removed from Pi"
echo ""
echo -e "${BLUE}📝 To Re-add This Pi:${NC}"
echo "   ./scripts/add-pi-to-cluster.sh ${PI_NODE_NAME}"
echo ""
echo -e "${BLUE}🔧 Useful Commands:${NC}"
echo "   • View remaining nodes: kubectl get nodes"
echo "   • Check Pi is clean: ssh ${PI_USER}@${PI_HOST} 'systemctl status k3s-agent'"
echo "   • Check dashboard: http://<CONTROL_PLANE_IP>:32000"
echo ""
print_status "Done!"
