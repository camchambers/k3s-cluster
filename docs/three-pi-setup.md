# Three Pi Zero 2W Setup Guide

**Date**: May 16, 2026  
**Cluster Configuration**: 3x Pi Zero 2W with DietPi

---

## Pi Zero Inventory

| Node | Hostname | User | OS | RAM |
|------|----------|------|-----|-----|
| pi1 | pi1.local | root | DietPi | 512MB |
| pi2 | pi2.local | root | DietPi | 512MB |
| pi3 | pi3.local | root | DietPi | 512MB |

**Control Plane**: `<control-plane-node>` (`<CONTROL_PLANE_IP>`, 32GB RAM, amd64)

---

## Initial K3s Agent Setup

### Easy Way (Automated Script)

Use the provided script to add each Pi with a single command:

```bash
cd k3_cluster

# Add each Pi to cluster:
./scripts/add-pi-to-cluster.sh pi1
./scripts/add-pi-to-cluster.sh pi2
./scripts/add-pi-to-cluster.sh pi3
```

The script will:
- Automatically get the K3s token from control plane
- Test SSH connectivity
- Show Pi information (OS, architecture, memory)
- Install K3s agent
- Wait for node to join and become Ready
- Display helpful next steps

### Manual Way

Run on **each Pi** (pi1.local, pi2.local, pi3.local) as root:

```bash
# Get K3s token from control plane (run once on your desktop)
K3S_TOKEN=$(ssh <your-username>@<CONTROL_PLANE_IP> "sudo cat /var/lib/rancher/k3s/server/node-token")
echo $K3S_TOKEN

# On pi1.local (as root):
curl -sfL https://get.k3s.io | \
  K3S_URL=https://<CONTROL_PLANE_IP>:6443 \
  K3S_TOKEN=<paste-token-here> \
  K3S_NODE_NAME=pi1 \
  sh -s - agent

# On pi2.local (as root):
curl -sfL https://get.k3s.io | \
  K3S_URL=https://<CONTROL_PLANE_IP>:6443 \
  K3S_TOKEN=<paste-token-here> \
  K3S_NODE_NAME=pi2 \
  sh -s - agent

# On pi3.local (as root):
curl -sfL https://get.k3s.io | \
  K3S_URL=https://<CONTROL_PLANE_IP>:6443 \
  K3S_TOKEN=<paste-token-here> \
  K3S_NODE_NAME=pi3 \
  sh -s - agent
```

---

## Verify Cluster

```bash
# Check all nodes are Ready
kubectl get nodes

# Expected output:
# NAME                   STATUS   ROLES                  AGE   VERSION
# <control-plane-node>   Ready    control-plane,master   Xd    v1.35.4+k3s1
# pi1                    Ready    <none>                 Xm    v1.35.4+k3s1
# pi2                    Ready    <none>                 Xm    v1.35.4+k3s1
# pi3                    Ready    <none>                 Xm    v1.35.4+k3s1

# Check node resources
kubectl top nodes
```

---

## Deploy Monitoring Stack

Once all three Pis are joined:

```bash
cd k3_cluster
./scripts/deploy-observability.sh
```

This will:
- Deploy Prometheus, Grafana, node-exporter to the cluster
- node-exporter DaemonSet runs on **all 4 nodes** (desktop + 3 Pis)
- WiFi metrics collected from all Pi Zeros
- Dashboard accessible at: http://<CONTROL_PLANE_IP>:32000

---

## Optimize Pi Memory (Optional)

Run the optimization script to reduce K3s memory footprint on Pis:

```bash
cd k3_cluster
./scripts/optimize-pi-k3s.sh

# Menu options:
# 1) Optimize pi1 only
# 2) Optimize pi2 only
# 3) Optimize pi3 only
# 4) Optimize all Pis (recommended)

# Phase options:
# Phase 1: Safe (~40-60MB saved)
# Phase 2: Aggressive (~50-70MB saved, monitor closely)
```

---

## Expected Memory Usage

### Before Optimization:
```
Each Pi Zero (512MB total):
├── ~177 MB (35%) - K3s system
├──  11 MB ( 2%) - node-exporter monitoring
├──  ~7 MB ( 1%) - Your apps
└── 317 MB (62%) - FREE
```

### After Phase 1 Optimization:
```
Each Pi Zero (512MB total):
├── ~130 MB (25%) - K3s system (-47MB!)
├──  11 MB ( 2%) - node-exporter
├──  ~7 MB ( 1%) - Your apps
└── 364 MB (71%) - FREE
```

### After Phase 2 Optimization:
```
Each Pi Zero (512MB total):
├── ~110 MB (21%) - K3s system (-67MB!)
├──  11 MB ( 2%) - node-exporter
├──  ~7 MB ( 1%) - Your apps
└── 384 MB (75%) - FREE
```

---

## Deploying Applications to Pis

To schedule pods on Pi Zeros (after optimization, which adds node taints):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-edge-app
spec:
  template:
    spec:
      # Add toleration to run on Pi Zeros
      tolerations:
        - key: "workload"
          operator: "Equal"
          value: "edge"
          effect: "NoSchedule"
      
      # Optional: Force scheduling to Pi nodes only
      nodeSelector:
        kubernetes.io/hostname: pi1  # or pi2, pi3
      
      # Or use node affinity for any Pi:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.io/hostname
                    operator: In
                    values:
                      - pi1
                      - pi2
                      - pi3
```

---

## Monitoring Dashboard

Access Grafana at: http://<CONTROL_PLANE_IP>:32000/d/k3s-pi-cluster-monitor

**Panels showing data for all 3 Pis:**
- Pi Zero Memory % (shows all Pis)
- Pi Zero WiFi Signal (shows all connected Pis)
- Top Memory Consumers by Node (table view)
- CPU/Memory metrics (filtered by `.*pi.*`)

The dashboard automatically detects all nodes matching the pattern `pi*` - no changes needed!

---

## Common Operations

### Check Pi Status:
```bash
kubectl get nodes | grep pi
kubectl top nodes | grep pi
```

### View Pods on Pis:
```bash
kubectl get pods -A -o wide | grep -E "pi1|pi2|pi3"
```

### Add a Pi to Cluster:
```bash
# Easy way (automated):
./scripts/add-pi-to-cluster.sh pi1

# Manual way (on the Pi as root):
curl -sfL https://get.k3s.io | \
  K3S_URL=https://<CONTROL_PLANE_IP>:6443 \
  K3S_TOKEN=$(ssh <your-username>@<CONTROL_PLANE_IP> "sudo cat /var/lib/rancher/k3s/server/node-token") \
  K3S_NODE_NAME=pi1 \
  sh -s - agent
```

### Remove a Pi from Cluster:
```bash
# Easy way (automated - drains, deletes, and cleans up):
./scripts/remove-pi-from-cluster.sh pi1

# Manual way:
# 1. Drain and delete from cluster:
kubectl drain pi1 --ignore-daemonsets --delete-emptydir-data --force
kubectl delete node pi1

# 2. Clean up on the Pi (as root):
ssh root@pi1.local /usr/local/bin/k3s-agent-uninstall.sh
```

---

## Troubleshooting

### Pi Not Joining Cluster:
```bash
# On the Pi:
systemctl status k3s-agent
journalctl -u k3s-agent -f

# Check network connectivity:
ping <CONTROL_PLANE_IP>
```

### High Memory on Pi:
```bash
# Check what's running:
kubectl get pods -A -o wide | grep pi1  # or pi2, pi3

# Check memory breakdown:
kubectl top node pi1
kubectl top pods -A --sort-by=memory | grep pi1
```

### WiFi Metrics Not Showing:
```bash
# SSH to Pi and check:
ssh root@pi1.local
ip link show | grep wlan  # Should show wlan0
iwconfig wlan0  # Should show signal strength

# Check node-exporter metrics:
curl localhost:9100/metrics | grep wifi
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Add Pi to cluster | `./scripts/add-pi-to-cluster.sh pi1` |
| Remove Pi from cluster | `./scripts/remove-pi-from-cluster.sh pi1` |
| Deploy monitoring | `./scripts/deploy-observability.sh` |
| Optimize Pis | `./scripts/optimize-pi-k3s.sh` |
| Remove monitoring | `./scripts/uninstall-observability.sh` |
| View dashboard | `http://<CONTROL_PLANE_IP>:32000` |
| Check nodes | `kubectl get nodes` |
| Check Pi memory | `kubectl top nodes \| grep pi` |
| View Pi pods | `kubectl get pods -A -o wide \| grep pi` |

---

## Notes

- **DietPi Benefits**: ~50MB lower base memory usage vs Raspberry Pi OS
- **Root User**: All scripts configured for `root` user (DietPi default)
- **Hostnames**: Using `.local` mDNS names instead of IP addresses
- **Auto-Discovery**: Dashboard and monitoring automatically detect all Pi nodes
- **Scalable**: Can add more Pis (pi4, pi5, etc.) without configuration changes
