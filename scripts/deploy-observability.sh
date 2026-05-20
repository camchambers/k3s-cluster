#!/bin/bash
#
# K3s Pi Cluster Observability - Turn-Key Deployment
#
# This script deploys the complete monitoring stack (Prometheus + Grafana)
# to a K3s cluster with mixed architecture (amd64 desktop + arm64 Pi Zeros).
#
# Prerequisites:
#   - K3s cluster running
#   - kubectl configured
#   - sudo access on nodes for storage setup

set -e

# Change to project root (parent of scripts directory)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="monitoring"
GRAFANA_PORT="32000"
PROMETHEUS_RETENTION_DAYS="90"
PROMETHEUS_RETENTION_SIZE="50GB"
SCRAPE_INTERVAL="60s"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  K3s Pi Cluster Observability - Turn-Key Deployment${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

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

# Check prerequisites
echo -e "${BLUE}[1/7] Checking prerequisites...${NC}"

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found. Please install kubectl."
    exit 1
fi
print_status "kubectl found"

if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to K3s cluster. Check kubectl configuration."
    exit 1
fi
print_status "K3s cluster accessible"

# Get cluster info
CONTROL_PLANE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}')
WORKER_COUNT=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers 2>/dev/null | wc -l)

print_info "Control plane: $CONTROL_PLANE"
print_info "Worker nodes: $WORKER_COUNT"
echo ""

# Setup storage directories
echo -e "${BLUE}[2/7] Setting up storage directories...${NC}"

print_info "This requires sudo access to create directories with specific ownership"
echo ""

# Create Prometheus storage (UID 65534 = nobody)
if [ ! -d "/mnt/prometheus-data" ]; then
    print_info "Creating /mnt/prometheus-data..."
    sudo mkdir -p /mnt/prometheus-data
    sudo chown -R 65534:65534 /mnt/prometheus-data
    sudo chmod 755 /mnt/prometheus-data
    print_status "Prometheus storage created"
else
    print_warning "Prometheus storage already exists, ensuring correct permissions..."
    sudo chown -R 65534:65534 /mnt/prometheus-data
    print_status "Prometheus storage verified"
fi

# Create Grafana storage (UID 472 = grafana)
if [ ! -d "/mnt/grafana-data" ]; then
    print_info "Creating /mnt/grafana-data..."
    sudo mkdir -p /mnt/grafana-data
    sudo chown -R 472:472 /mnt/grafana-data
    sudo chmod 755 /mnt/grafana-data
    print_status "Grafana storage created"
else
    print_warning "Grafana storage already exists, ensuring correct permissions..."
    sudo chown -R 472:472 /mnt/grafana-data
    print_status "Grafana storage verified"
fi

echo ""

# Create namespace
echo -e "${BLUE}[3/7] Creating namespace...${NC}"

if kubectl get namespace $NAMESPACE &> /dev/null; then
    print_warning "Namespace '$NAMESPACE' already exists"
else
    kubectl apply -f manifests/observability/namespace.yaml
    print_status "Namespace '$NAMESPACE' created"
fi
echo ""

# Deploy components
echo -e "${BLUE}[4/7] Deploying monitoring components...${NC}"

print_info "Deploying in order:"
echo "  1. RBAC (ServiceAccounts, Roles, Bindings)"
echo "  2. ConfigMaps (Prometheus config, Alert rules, Grafana datasources, Dashboards)"
echo "  3. Workloads (Deployments, DaemonSets)"
echo "  4. Services (ClusterIP, NodePort)"
echo ""

# Deploy everything with proper ordering (exclude .json dashboard files)
print_info "Applying all manifests..."
# Apply all YAML/YML files, skip JSON dashboard files (they're imported separately)
find manifests/observability -type f \( -name "*.yaml" -o -name "*.yml" \) -exec kubectl apply -f {} \; 2>&1 | tail -10

print_status "All manifests applied"
echo ""

# Wait for pods to be ready
echo -e "${BLUE}[5/7] Waiting for pods to become ready...${NC}"

print_info "This may take 1-2 minutes..."
echo ""

# Wait for node-exporter (DaemonSet)
print_info "Waiting for node-exporter DaemonSet..."
kubectl rollout status daemonset/node-exporter -n $NAMESPACE --timeout=120s
print_status "node-exporter ready on all nodes"

# Wait for kube-state-metrics
print_info "Waiting for kube-state-metrics..."
kubectl rollout status deployment/kube-state-metrics -n $NAMESPACE --timeout=120s
print_status "kube-state-metrics ready"

# Wait for Prometheus
print_info "Waiting for Prometheus..."
kubectl rollout status deployment/prometheus -n $NAMESPACE --timeout=120s
print_status "Prometheus ready"

# Wait for Alertmanager
print_info "Waiting for Alertmanager..."
kubectl rollout status deployment/alertmanager -n $NAMESPACE --timeout=120s
print_status "Alertmanager ready"

# Wait for Grafana
print_info "Waiting for Grafana..."
kubectl rollout status deployment/grafana -n $NAMESPACE --timeout=120s
print_status "Grafana ready"

echo ""

# Verify deployment
echo -e "${BLUE}[6/7] Verifying deployment...${NC}"

# Check all pods are running
TOTAL_PODS=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
RUNNING_PODS=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

if [ "$TOTAL_PODS" -eq "$RUNNING_PODS" ]; then
    print_status "All $RUNNING_PODS pods running"
else
    print_warning "$RUNNING_PODS/$TOTAL_PODS pods running"
fi

# Get Grafana NodePort
GRAFANA_NODE_PORT=$(kubectl get svc grafana -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}')
GRAFANA_NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' | awk '{print $1}')

print_status "Services deployed"
echo ""

# Display summary
echo -e "${BLUE}[7/7] Deployment Summary${NC}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✓ Monitoring Stack Successfully Deployed!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}📊 Grafana Dashboard:${NC}"
echo "   URL: http://$GRAFANA_NODE_IP:$GRAFANA_NODE_PORT"
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo -e "${BLUE}📈 Components:${NC}"
echo "   • Prometheus: Time-series database (${PROMETHEUS_RETENTION_DAYS}/${PROMETHEUS_RETENTION_SIZE} retention)"
echo "   • Grafana: Visualization & dashboards"
echo "   • Alertmanager: Alert routing"
echo "   • node-exporter: Node-level metrics (all nodes)"
echo "   • kube-state-metrics: Kubernetes resource metrics"
echo ""
echo -e "${BLUE}🎯 Pre-configured Dashboards:${NC}"
echo "   • K3s Pi Cluster Monitor (custom dashboard)"
echo "   • Node Exporter Full (detailed node metrics)"
echo ""
echo -e "${BLUE}📦 Pods Status:${NC}"
kubectl get pods -n $NAMESPACE -o wide
echo ""
echo -e "${BLUE}🔧 Services:${NC}"
kubectl get svc -n $NAMESPACE
echo ""
echo -e "${BLUE}💾 Storage:${NC}"
echo "   Prometheus: /mnt/prometheus-data ($(sudo du -sh /mnt/prometheus-data 2>/dev/null | cut -f1))"
echo "   Grafana: /mnt/grafana-data ($(sudo du -sh /mnt/grafana-data 2>/dev/null | cut -f1))"
echo ""
echo -e "${BLUE}📝 Next Steps:${NC}"
echo "   1. Open Grafana: http://$GRAFANA_NODE_IP:$GRAFANA_NODE_PORT"
echo "   2. Navigate to 'K3s Pi Cluster Monitor' dashboard"
echo "   3. Wait 2-3 minutes for initial metrics to populate"
echo "   4. Configure alert receivers in Alertmanager (optional)"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
print_info "To access Prometheus UI:"
echo "   kubectl port-forward -n $NAMESPACE svc/prometheus 9090:9090"
echo "   Then open: http://localhost:9090"
echo ""
print_info "To access Alertmanager UI:"
echo "   kubectl port-forward -n $NAMESPACE svc/alertmanager 9093:9093"
echo "   Then open: http://localhost:9093"
echo ""
print_info "To view logs:"
echo "   kubectl logs -n $NAMESPACE -l app=prometheus --tail=50"
echo "   kubectl logs -n $NAMESPACE -l app=grafana --tail=50"
echo ""
print_status "Deployment complete!"
