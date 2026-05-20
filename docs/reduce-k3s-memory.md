# Reducing K3s Memory Overhead on Pi Zero 2W

## Current Memory Usage Analysis

```
512MB Total RAM:
├── 195 Mi Used (47%)
│   ├── ~177 Mi (91%) ← K3s system + kernel
│   ├──   11 Mi ( 6%) ← node-exporter monitoring
│   ├──    6 Mi ( 3%) ← Your camera apps
│   └──    1 Mi (<1%) ← Traefik load balancer
└── 317 Mi Free
```

**Problem**: K3s baseline consumes ~177MB before running any applications.

---

## Recommendations (Ordered by Impact)

### 1. ✅ Disable Unused K3s Components (HIGHEST IMPACT: ~30-50MB)

K3s includes several components that may not be needed on a worker node:

```bash
# Reinstall K3s on Pi Zero as a minimal agent
# Run on each Pi: pi1.local, pi2.local, pi3.local (as root)
curl -sfL https://get.k3s.io | K3S_URL=https://<CONTROL_PLANE_IP>:6443 \
  K3S_TOKEN=$(ssh <your-username>@<CONTROL_PLANE_IP> "sudo cat /var/lib/rancher/k3s/server/node-token") \
  sh -s - agent \
  --disable servicelb \
  --disable traefik \
  --disable local-storage \
  --node-name pi1  # Change to pi2, pi3 for each Pi

# What gets disabled:
# - servicelb: K3s service load balancer (klipper-lb) - saves ~10-15MB
# - traefik: Ingress controller - saves ~15-20MB
# - local-storage: Storage provisioner - saves ~5-10MB
```

**Impact**: 30-50MB saved  
**Trade-off**: These services still run on desktop node, just not on Pi

---

### 2. ✅ Tune Kubelet Settings (MEDIUM IMPACT: ~15-25MB)

Reduce kubelet memory overhead with optimized settings:

```bash
# Add to K3s agent install command or /etc/systemd/system/k3s-agent.service.d/override.conf
--kubelet-arg="max-pods=20" \              # Default 110 - reduce for Pi
--kubelet-arg="image-gc-high-threshold=60" \  # More aggressive garbage collection
--kubelet-arg="image-gc-low-threshold=40" \
--kubelet-arg="eviction-hard=memory.available<50Mi" \
--kubelet-arg="eviction-soft=memory.available<100Mi" \
--kubelet-arg="eviction-soft-grace-period=memory.available=1m30s" \
--kubelet-arg="kube-reserved=memory=30Mi,cpu=50m" \  # Reserve less for K3s
--kubelet-arg="system-reserved=memory=50Mi,cpu=100m"  # Reserve less for system
```

**Impact**: 15-25MB saved  
**Trade-off**: More aggressive eviction, fewer max pods

---

### 3. ✅ Use Lightweight Container Runtime Settings (MEDIUM IMPACT: ~10-20MB)

```bash
# Add to K3s agent install
--container-runtime-endpoint /var/run/containerd/containerd.sock \
--kubelet-arg="container-log-max-files=2" \
--kubelet-arg="container-log-max-size=1Mi"
```

**Impact**: 10-20MB saved  
**Trade-off**: Less log retention

---

### 4. ✅ Disable Unnecessary CNI Features (LOW-MEDIUM IMPACT: ~5-15MB)

K3s uses Flannel by default. You can reduce its footprint:

```bash
# Add to K3s agent install
--flannel-backend=host-gw  # Instead of vxlan (lower overhead)
```

**Impact**: 5-15MB saved  
**Trade-off**: Requires nodes on same L2 network (you already have this)

---

### 5. ⚠️ Add Node Taints to Prevent Accidental Scheduling (NO MEMORY SAVED, BUT PROTECTS PI)

```bash
# Prevent non-essential pods from landing on Pi Zeros
# Apply to all Pi nodes:
kubectl taint nodes pi1 workload=edge:NoSchedule
kubectl taint nodes pi2 workload=edge:NoSchedule
kubectl taint nodes pi3 workload=edge:NoSchedule

# Your apps can override with tolerations:
tolerations:
  - key: "workload"
    operator: "Equal"
    value: "edge"
    effect: "NoSchedule"
```

**Impact**: Prevents memory issues from accidental scheduling  
**Trade-off**: Must explicitly tolerate to run on Pi

---

### 6. ⚠️ Consider Switching to K3s Agent-Only Mode (HIGHEST IMPACT: ~40-60MB)

Most aggressive option - run Pi as pure agent with absolute minimum:

```bash
# Run on each Pi Zero (pi1.local, pi2.local, pi3.local) as root
# Uninstall current K3s
/usr/local/bin/k3s-agent-uninstall.sh

# Reinstall as ultra-minimal agent
curl -sfL https://get.k3s.io | K3S_URL=https://<CONTROL_PLANE_IP>:6443 \
  K3S_TOKEN=$(ssh <your-username>@<CONTROL_PLANE_IP> "sudo cat /var/lib/rancher/k3s/server/node-token") \
  K3S_NODE_NAME=pi1 \  # Change to pi2, pi3 for each Pi
  INSTALL_K3S_EXEC="agent \
    --disable servicelb \
    --disable traefik \
    --disable local-storage \
    --flannel-backend=host-gw \
    --kubelet-arg=max-pods=20 \
    --kubelet-arg=image-gc-high-threshold=60 \
    --kubelet-arg=image-gc-low-threshold=40 \
    --kubelet-arg=eviction-hard=memory.available<40Mi \
    --kubelet-arg=kube-reserved=memory=20Mi \
    --kubelet-arg=system-reserved=memory=40Mi \
    --kubelet-arg=container-log-max-files=2 \
    --kubelet-arg=container-log-max-size=1Mi" \
  sh -
```

**Impact**: 40-60MB saved (total K3s overhead down to ~120-140MB)  
**Trade-off**: Very aggressive settings, requires careful monitoring

---

## Recommended Implementation Plan

### Phase 1: Safe Optimizations (Minimal Risk)
1. ✅ **Disable unused components** (-30-50MB)
2. ✅ **Add node taints** (protection)
3. ✅ **Use host-gw Flannel backend** (-5-15MB)

**Expected Result**: ~150-160MB K3s overhead (down from 177MB)

### Phase 2: Aggressive Tuning (Monitor Carefully)
4. ✅ **Tune kubelet settings** (-15-25MB)
5. ✅ **Optimize container runtime** (-10-20MB)

**Expected Result**: ~120-140MB K3s overhead (saves ~50-70MB total)

---

## Implementation Script

```bash
#!/bin/bash
# File: scripts/optimize-pi-k3s.sh

set -e

echo "🔧 Optimizing K3s on Pi Zero 2W"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get K3s token from control plane
K3S_TOKEN=$(ssh <your-username>@<CONTROL_PLANE_IP> "sudo cat /var/lib/rancher/k3s/server/node-token")

# SSH to each Pi and reconfigure (example for pi1)
# Repeat for pi2.local and pi3.local
ssh root@pi1.local << 'EOF'
  # Uninstall existing K3s agent
  echo "📦 Uninstalling current K3s agent..."
  /usr/local/bin/k3s-agent-uninstall.sh || true

  # Wait for cleanup
  sleep 5

  # Reinstall with optimized settings
  echo "⚙️  Installing optimized K3s agent..."
  curl -sfL https://get.k3s.io | K3S_URL=https://<CONTROL_PLANE_IP>:6443 \
    K3S_TOKEN=$K3S_TOKEN \
    K3S_NODE_NAME=pi1 \  # Change to pi2, pi3 for each
    INSTALL_K3S_EXEC="agent \
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
      --kubelet-arg=container-log-max-size=1Mi" \
    sh -

  echo "✅ K3s agent optimized!"
EOF

# Wait for nodes to rejoin
echo ""
echo "⏳ Waiting for Pi nodes to rejoin cluster..."
sleep 10

# Verify nodes are ready
kubectl wait --for=condition=Ready node/pi1 --timeout=120s
kubectl wait --for=condition=Ready node/pi2 --timeout=120s
kubectl wait --for=condition=Ready node/pi3 --timeout=120s

# Add node taints
echo ""
echo "🔒 Adding node taints to protect Pi Zeros..."
kubectl taint nodes pi1 workload=edge:NoSchedule --overwrite
kubectl taint nodes pi2 workload=edge:NoSchedule --overwrite
kubectl taint nodes pi3 workload=edge:NoSchedule --overwrite

# Show results
echo ""
echo "✅ Optimization Complete!"
echo ""
echo "📊 New Memory Usage:"
kubectl top node pi1
kubectl top node pi2
kubectl top node pi3

echo ""
echo "⚠️  Note: Pods will need tolerations to schedule on Pi Zeros:"
echo ""
cat << 'YAML'
tolerations:
  - key: "workload"
    operator: "Equal"
    value: "edge"
    effect: "NoSchedule"
YAML
```

---

## Monitoring After Changes

Use the new **"Top Memory Consumers by Node"** table in Grafana to track:
- Which pods are running on each node
- Memory usage per pod
- Identify any unexpected pods on Pi

**Dashboard**: http://<CONTROL_PLANE_IP>:32000/d/k3s-pi-custom/k3s-pi-cluster-monitor

---

## Expected Final Memory State

```
After Phase 1 Optimization (Safe):
512MB Total:
├── ~160 Mi (31%) ← K3s system (down from 177Mi)
├──  11 Mi ( 2%) ← node-exporter
├── ~40 Mi ( 8%) ← Your apps
└── 301 Mi (59%) ← FREE for applications

After Phase 2 Optimization (Aggressive):
512MB Total:
├── ~130 Mi (25%) ← K3s system (down from 177Mi)
├──  11 Mi ( 2%) ← node-exporter
├── ~40 Mi ( 8%) ← Your apps
└── 331 Mi (65%) ← FREE for applications
```

---

## Roll Back Plan

If issues occur:

```bash
# On each Pi Zero (as root):
/usr/local/bin/k3s-agent-uninstall.sh

# Reinstall with original settings (repeat for each Pi):
curl -sfL https://get.k3s.io | K3S_URL=https://<CONTROL_PLANE_IP>:6443 \
  K3S_TOKEN=<token> \
  sh -s - agent --node-name pi1  # Change to pi2, pi3

# Remove taints:
kubectl taint nodes pi1 workload=edge:NoSchedule-
kubectl taint nodes pi2 workload=edge:NoSchedule-
kubectl taint nodes pi3 workload=edge:NoSchedule-
```

---

## References

- [K3s Advanced Options](https://docs.k3s.io/installation/configuration)
- [Kubelet Configuration](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/)
- [Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
