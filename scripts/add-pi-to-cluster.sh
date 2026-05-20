#!/bin/bash
#
# Add Pi Zero to K3s Cluster
#
# Usage: ./add-pi-to-cluster.sh <hostname>
# Example: ./add-pi-to-cluster.sh pi1
#
# This script:
#   1. Gets K3s token from control plane
#   2. SSHs to the Pi and installs K3s agent
#   3. Waits for node to join cluster
#   4. Verifies node is ready

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONTROL_PLANE="${CONTROL_PLANE_IP:?Error: Set CONTROL_PLANE_IP to your control plane IP address}"
CONTROL_PLANE_USER="${CONTROL_PLANE_USER:?Error: Set CONTROL_PLANE_USER to your SSH username on the control plane}"
PI_USER="root"
K3S_VERSION=""  # Leave empty for latest, or specify like "v1.35.4+k3s1"

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
    echo "  $0 pi1        # Add pi1.local to cluster as node 'pi1'"
    echo "  $0 pi2        # Add pi2.local to cluster as node 'pi2'"
    echo "  $0 pi3        # Add pi3.local to cluster as node 'pi3'"
    echo ""
    exit 1
fi

PI_NODE_NAME="$1"
PI_HOST="${PI_NODE_NAME}.home"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Add Pi Zero to K3s Cluster${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
print_info "Pi hostname: $PI_HOST"
print_info "Node name: $PI_NODE_NAME"
print_info "Control plane: $CONTROL_PLANE"
echo ""

# Check if node already exists
echo -e "${BLUE}[1/6] Checking if node already exists...${NC}"
if kubectl get node "$PI_NODE_NAME" &> /dev/null; then
    print_warning "Node '$PI_NODE_NAME' already exists in cluster"
    echo ""
    kubectl get node "$PI_NODE_NAME"
    echo ""
    read -p "Remove existing node and re-add? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Removing existing node..."
        kubectl delete node "$PI_NODE_NAME"
        print_status "Node removed from cluster"
        echo ""
        print_info "Uninstalling K3s agent on Pi..."
        ssh ${PI_USER}@${PI_HOST} "/usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || true"
        print_status "K3s agent uninstalled"
        sleep 5
    else
        print_info "Aborted"
        exit 0
    fi
else
    print_status "Node name '$PI_NODE_NAME' is available"
fi
echo ""

# Test SSH connectivity
echo -e "${BLUE}[2/5] Testing SSH connectivity to Pi...${NC}"
if ! ssh -o ConnectTimeout=5 ${PI_USER}@${PI_HOST} "echo 'SSH OK'" &> /dev/null; then
    print_error "Cannot connect to ${PI_USER}@${PI_HOST}"
    print_info "Check that:"
    echo "  1. Pi is powered on and connected to network"
    echo "  2. Hostname resolves: ping ${PI_HOST}"
    echo "  3. SSH is accessible: ssh ${PI_USER}@${PI_HOST}"
    exit 1
fi
print_status "SSH connection successful"

# Get Pi info
PI_OS=$(ssh ${PI_USER}@${PI_HOST} "cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2")
PI_ARCH=$(ssh ${PI_USER}@${PI_HOST} "uname -m")
PI_MEM=$(ssh ${PI_USER}@${PI_HOST} "free -m | awk 'NR==2{print \$2}'")" MB"

print_info "OS: $PI_OS"
print_info "Architecture: $PI_ARCH"
print_info "Memory: $PI_MEM"
echo ""

# Check and enable cgroup memory support (required for K3s)
echo -e "${BLUE}[3/6] Checking cgroup memory support...${NC}"
CGROUP_CHECK=$(ssh ${PI_USER}@${PI_HOST} "grep -q 'cgroup_memory=1' /boot/firmware/cmdline.txt && echo 'enabled' || echo 'missing'")

if [ "$CGROUP_CHECK" = "missing" ]; then
    print_info "Cgroup memory support not enabled, configuring..."
    
    # Backup and update cmdline.txt
    ssh ${PI_USER}@${PI_HOST} "
        cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.bak &&
        sed -i 's/$/ cgroup_memory=1 cgroup_enable=memory/' /boot/firmware/cmdline.txt
    "
    
    if [ $? -ne 0 ]; then
        print_error "Failed to update boot configuration"
        exit 1
    fi
    
    print_status "Cgroup configuration updated"
    print_info "Rebooting Pi to apply changes..."
    
    # Reboot the Pi
    ssh ${PI_USER}@${PI_HOST} "reboot" || true
    
    # Wait for Pi to go down
    sleep 5
    
    # Wait for Pi to come back up (max 2 minutes)
    print_info "Waiting for Pi to restart (max 2 minutes)..."
    REBOOT_TIMEOUT=120
    REBOOT_ELAPSED=0
    while [ $REBOOT_ELAPSED -lt $REBOOT_TIMEOUT ]; do
        if ssh -o ConnectTimeout=2 ${PI_USER}@${PI_HOST} "echo 'ready'" &> /dev/null; then
            print_status "Pi is back online"
            break
        fi
        sleep 5
        REBOOT_ELAPSED=$((REBOOT_ELAPSED + 5))
        echo -n "."
    done
    echo ""
    
    if [ $REBOOT_ELAPSED -ge $REBOOT_TIMEOUT ]; then
        print_error "Pi did not come back online after reboot"
        print_info "Please check the Pi and try again"
        exit 1
    fi
    
    # Give it a few more seconds to fully boot
    sleep 5
else
    print_status "Cgroup memory support already enabled"
fi
echo ""

# Get K3s token from control plane
echo -e "${BLUE}[4/6] Getting K3s token from control plane...${NC}"

# Check if we're on the control plane or need to SSH
CURRENT_IP=$(hostname -I | awk '{print $1}')
if [ "$CURRENT_IP" = "$CONTROL_PLANE" ]; then
    # We're on the control plane, read token directly
    K3S_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)
else
    # Remote control plane, SSH to get token
    K3S_TOKEN=$(ssh ${CONTROL_PLANE_USER}@${CONTROL_PLANE} "sudo cat /var/lib/rancher/k3s/server/node-token")
fi

if [ -z "$K3S_TOKEN" ]; then
  print_error "Failed to get K3s token"
  exit 1
fi
print_status "K3s token retrieved"
echo ""

# Install K3s agent on Pi
echo -e "${BLUE}[5/6] Installing K3s agent on Pi...${NC}"
print_info "This may take 1-2 minutes..."
echo ""

# Build install command
INSTALL_CMD="curl -sfL https://get.k3s.io | K3S_URL=https://${CONTROL_PLANE}:6443 K3S_TOKEN=${K3S_TOKEN} K3S_NODE_NAME=${PI_NODE_NAME}"

# Add version if specified
if [ -n "$K3S_VERSION" ]; then
    INSTALL_CMD="${INSTALL_CMD} INSTALL_K3S_VERSION=${K3S_VERSION}"
fi

INSTALL_CMD="${INSTALL_CMD} sh -s - agent"

# Run install on Pi
if ssh ${PI_USER}@${PI_HOST} "${INSTALL_CMD}"; then
    print_status "K3s agent installed successfully"
else
    print_error "Failed to install K3s agent"
    exit 1
fi
echo ""

# Wait for node to join cluster
echo -e "${BLUE}[6/6] Waiting for node to join cluster...${NC}"
print_info "Waiting for node to appear..."

# Wait up to 60 seconds for node to appear
TIMEOUT=60
ELAPSED=0
while ! kubectl get node "$PI_NODE_NAME" &> /dev/null; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    if [ $ELAPSED -ge $TIMEOUT ]; then
        print_error "Timeout waiting for node to join cluster"
        print_info "Check Pi logs: ssh ${PI_USER}@${PI_HOST} journalctl -u k3s-agent -f"
        exit 1
    fi
    echo -n "."
done
echo ""
print_status "Node joined cluster"

# Wait for node to be ready
print_info "Waiting for node to be Ready..."
if kubectl wait --for=condition=Ready node/${PI_NODE_NAME} --timeout=120s; then
    print_status "Node is Ready"
else
    print_error "Node did not become Ready within timeout"
    exit 1
fi
echo ""

# Show summary
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✓ Pi Successfully Added to Cluster!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}📋 Node Information:${NC}"
kubectl get node "$PI_NODE_NAME" -o wide
echo ""
echo -e "${BLUE}🎯 Node Status:${NC}"
kubectl describe node "$PI_NODE_NAME" | grep -A 5 "Conditions:"
echo ""
echo -e "${BLUE}💾 Node Resources:${NC}"
kubectl top node "$PI_NODE_NAME" 2>/dev/null || echo "  Metrics not available yet (metrics-server needs time to collect data)"
echo ""
echo -e "${BLUE}📝 Next Steps:${NC}"
echo "   1. Wait 2-3 minutes for metrics to populate"
echo "   2. Deploy monitoring (if not already): ./scripts/deploy-observability.sh"
echo "   3. Optimize Pi memory (optional): ./scripts/optimize-pi-k3s.sh"
echo "   4. View dashboard: http://${CONTROL_PLANE}:32000"
echo ""
echo -e "${BLUE}🔧 Useful Commands:${NC}"
echo "   • View all nodes: kubectl get nodes"
echo "   • Check Pi status: kubectl describe node ${PI_NODE_NAME}"
echo "   • View Pi logs: ssh ${PI_USER}@${PI_HOST} journalctl -u k3s-agent -f"
echo "   • Remove node: ./scripts/remove-pi-from-cluster.sh ${PI_NODE_NAME}"
echo ""
print_status "Done!"
