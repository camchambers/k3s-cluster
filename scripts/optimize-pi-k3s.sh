#!/bin/bash
# Optimize K3s on Pi Zero 2W for minimal memory footprint
# This script reconfigures the Pi Zero K3s agent with aggressive memory optimizations

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 K3s Pi Zero Memory Optimization${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Configuration
CONTROL_PLANE="${CONTROL_PLANE_IP:?Error: Set CONTROL_PLANE_IP to your control plane IP address}"
CONTROL_PLANE_USER="${CONTROL_PLANE_USER:?Error: Set CONTROL_PLANE_USER to your SSH username on the control plane}"
PI_USER="root"

# Available Pi nodes (DietPi with root user)
declare -A PI_NODES
PI_NODES["pi1"]="pi1.home"
PI_NODES["pi2"]="pi2.home"
PI_NODES["pi3"]="pi3.home"

# Select which Pis to optimize
echo -e "${YELLOW}Select Pi Zero(s) to optimize:${NC}"
echo "1) pi1 only (pi1.local)"
echo "2) pi2 only (pi2.local)"
echo "3) pi3 only (pi3.local)"
echo "4) All Pis (pi1, pi2, pi3)"
echo ""
read -p "Enter choice (1-4): " PI_CHOICE

case $PI_CHOICE in
  1)
    SELECTED_PIS=("pi1")
    ;;
  2)
    SELECTED_PIS=("pi2")
    ;;
  3)
    SELECTED_PIS=("pi3")
    ;;
  4)
    SELECTED_PIS=("pi1" "pi2" "pi3")
    ;;
  *)
    echo -e "${RED}❌ Invalid choice. Exiting.${NC}"
    exit 1
    ;;
esac

# Phase selection
echo ""
echo -e "${YELLOW}Select optimization phase:${NC}"
echo "1) Phase 1: Safe optimizations (~40-60MB saved)"
echo "   - Disable unused components (servicelb, traefik, local-storage)"
echo "   - Use host-gw flannel backend"
echo "   - Add protective node taint"
echo ""
echo "2) Phase 2: Aggressive tuning (~50-70MB saved total)"
echo "   - All Phase 1 optimizations"
echo "   - Aggressive kubelet tuning"
echo "   - Container runtime optimization"
echo "   - Reduced resource reservations"
echo ""
read -p "Enter choice (1 or 2): " PHASE

if [[ ! "$PHASE" =~ ^[12]$ ]]; then
  echo -e "${RED}❌ Invalid choice. Exiting.${NC}"
  exit 1
fi

# Confirmation
echo ""
echo -e "${YELLOW}⚠️  This will optimize: ${SELECTED_PIS[@]}${NC}"
echo ""
echo "   1. Uninstall K3s agent on selected Pi(s)"
echo "   2. Reinstall with optimized settings"
echo "   3. Wait for node(s) to rejoin cluster"
if [ "$PHASE" = "1" ]; then
  echo "   4. Add node taint (workload=edge:NoSchedule)"
else
  echo "   4. Apply aggressive tuning"
  echo "   5. Add node taint (workload=edge:NoSchedule)"
fi
echo ""
read -p "Continue? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo -e "${BLUE}📋 Step 1: Getting K3s token from control plane${NC}"

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
  echo -e "${RED}❌ Failed to get K3s token${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Token retrieved${NC}"

# Process each selected Pi
for PI_NODE_NAME in "${SELECTED_PIS[@]}"; do
  PI_HOST="${PI_NODES[$PI_NODE_NAME]}"
  
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  Processing: $PI_NODE_NAME ($PI_HOST)${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  echo ""
  echo -e "${BLUE}📋 Step 2: Backing up current memory usage for $PI_NODE_NAME${NC}"
  kubectl top node ${PI_NODE_NAME} 2>/dev/null || echo "  Could not get current metrics for $PI_NODE_NAME"

  echo ""
  echo -e "${BLUE}📋 Step 3: Uninstalling K3s agent on $PI_NODE_NAME${NC}"
  ssh ${PI_USER}@${PI_HOST} "/usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || true"
  echo -e "${GREEN}✅ Uninstall complete for $PI_NODE_NAME${NC}"

  # Wait for cleanup
  echo -e "${BLUE}⏳ Waiting for cleanup (10s)...${NC}"
  sleep 10

  # Build install command based on phase
  echo ""
  echo -e "${BLUE}📋 Step 4: Installing optimized K3s agent on $PI_NODE_NAME (Phase ${PHASE})${NC}"

  if [ "$PHASE" = "1" ]; then
    # Phase 1: Safe optimizations
    INSTALL_CMD="curl -sfL https://get.k3s.io | K3S_URL=https://${CONTROL_PLANE}:6443 \
      K3S_TOKEN=${K3S_TOKEN} \
      K3S_NODE_NAME=${PI_NODE_NAME} \
      INSTALL_K3S_EXEC='agent \
        --disable servicelb \
        --disable traefik \
        --disable local-storage \
        --flannel-backend=host-gw' \
      sh -"
  else
    # Phase 2: Aggressive tuning
    INSTALL_CMD="curl -sfL https://get.k3s.io | K3S_URL=https://${CONTROL_PLANE}:6443 \
      K3S_TOKEN=${K3S_TOKEN} \
      K3S_NODE_NAME=${PI_NODE_NAME} \
      INSTALL_K3S_EXEC='agent \
        --disable servicelb \
        --disable traefik \
        --disable local-storage \
        --flannel-backend=host-gw \
        --kubelet-arg=max-pods=20 \
        --kubelet-arg=image-gc-high-threshold=60 \
        --kubelet-arg=image-gc-low-threshold=40 \
        --kubelet-arg=eviction-hard=memory.available<50Mi \
        --kubelet-arg=eviction-soft=memory.available<100Mi \
        --kubelet-arg=eviction-soft-grace-period=memory.available=1m30s \
        --kubelet-arg=kube-reserved=memory=25Mi,cpu=50m \
        --kubelet-arg=system-reserved=memory=50Mi,cpu=100m \
        --kubelet-arg=container-log-max-files=2 \
        --kubelet-arg=container-log-max-size=1Mi' \
      sh -"
  fi

  ssh ${PI_USER}@${PI_HOST} "$INSTALL_CMD"
  echo -e "${GREEN}✅ K3s agent installed with optimizations on $PI_NODE_NAME${NC}"

  echo ""
  echo -e "${BLUE}📋 Step 5: Waiting for $PI_NODE_NAME to rejoin cluster${NC}"
  sleep 15

  # Wait for node to be ready
  echo "Waiting for node ${PI_NODE_NAME} to be Ready..."
  if kubectl wait --for=condition=Ready node/${PI_NODE_NAME} --timeout=120s; then
    echo -e "${GREEN}✅ Node $PI_NODE_NAME is Ready${NC}"
  else
    echo -e "${RED}❌ Node $PI_NODE_NAME did not become Ready within timeout${NC}"
    echo "Check with: kubectl get nodes"
    continue
  fi

  echo ""
  echo -e "${BLUE}📋 Step 6: Adding node taint to protect $PI_NODE_NAME${NC}"
  kubectl taint nodes ${PI_NODE_NAME} workload=edge:NoSchedule --overwrite
  echo -e "${GREEN}✅ Node taint applied to $PI_NODE_NAME${NC}"

done

# Summary for all nodes
echo ""
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Optimization Complete for: ${SELECTED_PIS[@]}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}📊 New Memory Usage:${NC}"
for PI_NODE_NAME in "${SELECTED_PIS[@]}"; do
  kubectl top node ${PI_NODE_NAME} 2>/dev/null || echo "  Could not get metrics for $PI_NODE_NAME"
done

echo ""
echo -e "${BLUE}📦 Running Pods on Pi Zeros:${NC}"
kubectl get pods --all-namespaces -o wide | grep -E "pi1|pi2|pi3" || echo "  No pods running on Pis yet"

echo ""
echo -e "${BLUE}📈 View dashboard:${NC}"
echo "   http://${CONTROL_PLANE}:32000/d/k3s-pi-cluster-monitor"
echo ""
echo -e "${YELLOW}⚠️  Note: Pods need this toleration to schedule on Pi Zeros:${NC}"
echo ""
echo "   Pods will need this toleration to run on Pi Zeros:"
echo "   tolerations:"
echo "     - key: \"workload\""
echo "       operator: \"Equal\""
echo "       value: \"edge\""
echo "       effect: \"NoSchedule\""
echo ""
if [ "$PHASE" = "2" ]; then
  echo -e "${YELLOW}⚠️  Phase 2 uses aggressive settings - monitor closely!${NC}"
  echo "   Watch for pod evictions or OOM events"
  echo ""
fi
echo -e "${BLUE}🔙 Rollback (if needed):${NC}"
echo "   For each Pi, run:"
echo "   ssh ${PI_USER}@pi[1|2|3].local '/usr/local/bin/k3s-agent-uninstall.sh'"
echo "   curl -sfL https://get.k3s.io | K3S_URL=https://${CONTROL_PLANE}:6443 K3S_TOKEN=<token> sh -s - agent --node-name pi[1|2|3]"
echo "   kubectl taint nodes pi[1|2|3] workload=edge:NoSchedule-"
echo ""
