# K3s Pi Cluster Observability Stack

Complete monitoring solution for K3s clusters with mixed architecture (amd64 + arm64 Pi Zeros).

## 🚀 Quick Start (Turn-Key Deployment)

**Deploy the entire stack in one command:**

```bash
chmod +x scripts/deploy-observability.sh
./scripts/deploy-observability.sh
```

That's it! The script will:
- ✅ Check prerequisites
- ✅ Create storage directories with correct permissions
- ✅ Deploy all components in proper order
- ✅ Wait for pods to be ready
- ✅ Verify deployment
- ✅ Display access information

**Access Grafana:**
```
http://<your-node-ip>:32000
Username: admin
Password: admin
```

## 📊 What You Get

### Pre-configured Dashboards
1. **K3s Pi Cluster Monitor** (custom) - Optimized for Pi Zero monitoring
   - Cluster-wide CPU, memory, disk metrics
   - Top CPU/memory consuming pods
   - Pi Zero specific health gauge
   - Node storage visualization
   - Pod restart tracking

2. **Node Exporter Full** - Detailed node-level metrics
   - Individual node performance (desktop vs Pi)
   - System load, network I/O
   - Filesystem usage

### Monitoring Components

| Component | Purpose | Architecture |
|-----------|---------|--------------|
| **Prometheus** | Time-series database & scraper | amd64 only |
| **Grafana** | Visualization & dashboards | amd64 only |
| **Alertmanager** | Alert routing & grouping | amd64 only |
| **node-exporter** | Host metrics (CPU, memory, disk) | DaemonSet (all nodes) |
| **kube-state-metrics** | Kubernetes resource metrics | amd64 only |

### Key Features
- ✅ **Auto-scaling**: Works with 1-10+ Pi Zeros automatically
- ✅ **Auto-provisioned dashboards**: No manual import needed
- ✅ **Persistent storage**: Survives restarts
- ✅ **Low Pi overhead**: <50MB memory on Pi Zero
- ✅ **90-day retention**: 50GB TSDB storage
- ✅ **No advertising**: Clean Grafana UI

## 📋 Prerequisites

- K3s cluster running (v1.28+)
- kubectl configured to access cluster
- sudo access on control plane node (for storage setup)
- At least 2GB free disk space on control plane

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     K3s Cluster                             │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Control Plane (amd64)           Pi Zero Workers (arm64)    │
│  ┌──────────────────┐            ┌──────────────────┐      │
│  │                  │            │                  │      │
│  │  Prometheus      │◄───────────┤  node-exporter   │      │
│  │  Grafana         │            │                  │      │
│  │  Alertmanager    │            └──────────────────┘      │
│  │  kube-state-     │            ┌──────────────────┐      │
│  │    metrics       │◄───────────┤  node-exporter   │      │
│  │  node-exporter   │            │                  │      │
│  │                  │            └──────────────────┘      │
│  └──────────────────┘            ┌──────────────────┐      │
│         ▲                        │  node-exporter   │      │
│         │                        │                  │      │
│         │                        └──────────────────┘      │
│         │ scrape                           ...             │
│         │ (60s interval)                                    │
│         │                                                   │
│  ┌──────┴───────┐                                          │
│  │  Grafana UI  │  ← http://node-ip:32000                 │
│  └──────────────┘                                          │
└─────────────────────────────────────────────────────────────┘
```

## 🔧 Configuration

### Scrape Interval
Currently: **60 seconds** (safe for Pi Zero's 512MB RAM)

To adjust, edit [prometheus/config.yaml](prometheus/config.yaml):
```yaml
global:
  scrape_interval: 60s  # Change this value
```

### Retention Period
Currently: **90 days / 50GB**

To adjust, edit [prometheus/deployment.yaml](prometheus/deployment.yaml):
```yaml
args:
  - --storage.tsdb.retention.time=90d  # Days to keep
  - --storage.tsdb.retention.size=50GB  # Max disk usage
```

### Alert Rules
Edit [prometheus/rules.yaml](prometheus/rules.yaml) to customize:
- Thresholds (memory/CPU/disk)
- Alert durations (how long before firing)
- Severity levels

Current alerts:
- NodeDown (2m)
- HighMemoryUsage (85%, 5m)
- CriticalMemoryUsage (95%, 2m)
- HighCPUUsage (80%, 10m)
- DiskSpaceLow (15%, 5m)
- DiskSpaceCritical (5%, 2m)
- PrometheusStorageHigh (45GB, 5m)

### Pi Zero Resource Limits
node-exporter uses **30Mi/50Mi** memory limits to protect Pi Zeros.

To adjust, edit [node-exporter/daemonset.yaml](node-exporter/daemonset.yaml):
```yaml
resources:
  requests:
    memory: 30Mi
  limits:
    memory: 50Mi
```

## 📦 Manual Deployment Steps

If you prefer manual control:

### 1. Create Storage Directories
```bash
sudo mkdir -p /mnt/prometheus-data /mnt/grafana-data
sudo chown -R 65534:65534 /mnt/prometheus-data  # UID 65534 = nobody
sudo chown -R 472:472 /mnt/grafana-data          # UID 472 = grafana
```

### 2. Deploy Components
```bash
# Deploy everything at once
kubectl apply -f manifests/observability/ --recursive

# OR deploy step-by-step
kubectl apply -f manifests/observability/namespace.yaml
kubectl apply -f manifests/observability/node-exporter/
kubectl apply -f manifests/observability/kube-state-metrics/
kubectl apply -f manifests/observability/prometheus/
kubectl apply -f manifests/observability/alertmanager/
kubectl apply -f manifests/observability/grafana/
```

### 3. Verify Deployment
```bash
# Check all pods are running
kubectl get pods -n monitoring

# Check services
kubectl get svc -n monitoring

# View Grafana logs
kubectl logs -n monitoring -l app=grafana --tail=50
```

### 4. Access Grafana
```bash
# Get NodePort
kubectl get svc grafana -n monitoring

# Open browser to:
http://<node-ip>:32000
```

## 🔍 Verification

### Check Prometheus Targets
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open: http://localhost:9090/targets
```

All targets should show **UP**:
- prometheus (1/1)
- node-exporter (N/N) - where N = number of nodes
- kube-state-metrics (1/1)
- kubelet (N/N)
- cadvisor (N/N)

### Test Metrics Collection
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open: http://localhost:9090/graph

# Try these queries:
node_memory_MemAvailable_bytes{instance=~".*pi.*"}  # Pi memory
rate(node_cpu_seconds_total[5m])                    # CPU usage
kube_pod_info                                       # All pods
```

## 🛠️ Troubleshooting

### Pods Not Starting

**Check pod status:**
```bash
kubectl get pods -n monitoring
kubectl describe pod <pod-name> -n monitoring
```

**Common issues:**
- Storage permissions: Ensure `/mnt/*-data` directories have correct ownership
- Resource constraints: Pi Zeros need at least 300MB free RAM
- Image pull issues: Check network connectivity

### No Data in Dashboards

**Wait 2-3 minutes** - Prometheus scrapes every 60 seconds, dashboards need multiple data points.

**Check Prometheus targets:**
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Visit: http://localhost:9090/targets
```

**Verify scraping is working:**
```bash
kubectl logs -n monitoring -l app=prometheus | grep "completed"
```

### Grafana Not Accessible

**Check service:**
```bash
kubectl get svc grafana -n monitoring
# Should show NodePort 32000
```

**Check pod logs:**
```bash
kubectl logs -n monitoring -l app=grafana --tail=50
```

**Check firewall:**
```bash
# Ensure port 32000 is open
sudo ufw status
sudo ufw allow 32000/tcp
```

### High Pi Memory Usage

**Check node-exporter memory:**
```bash
kubectl top pods -n monitoring -l app=node-exporter
```

**Should be <50MB**. If higher:
1. Check for memory leaks in logs
2. Consider reducing scrape frequency
3. Verify resource limits are applied

## 🗑️ Uninstall

```bash
chmod +x scripts/uninstall-observability.sh
./scripts/uninstall-observability.sh
```

You'll be prompted to:
1. Remove all monitoring components
2. Optionally delete persistent storage

**Manual uninstall:**
```bash
# Remove components
kubectl delete -f manifests/observability/ --recursive

# Remove namespace
kubectl delete namespace monitoring

# Optionally remove storage
sudo rm -rf /mnt/prometheus-data /mnt/grafana-data
```

## 📝 Customization

### Adding Dashboards

**Option 1: Grafana UI (Easiest)**
1. Create dashboard in Grafana
2. Export JSON
3. Save to: `manifests/observability/grafana/dashboards/`
4. Recreate ConfigMap:
   ```bash
   kubectl create configmap grafana-dashboards \
     --from-file=manifests/observability/grafana/dashboards/ \
     --namespace=monitoring \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

**Option 2: Import from grafana.com**
```bash
# In Grafana UI: + → Import → Enter dashboard ID
# Example IDs:
# 15760 - Kubernetes Views
# 10578 - Raspberry Pi Monitoring
# 1860 - Node Exporter Full
```

### Adding Custom Metrics

Add scrape configs to [prometheus/config.yaml](prometheus/config.yaml):
```yaml
scrape_configs:
  - job_name: 'my-app'
    static_configs:
      - targets: ['my-app-service:8080']
```

### Configuring Alert Receivers

Edit [alertmanager/config.yaml](alertmanager/config.yaml):

```yaml
receivers:
  - name: 'slack'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#alerts'

  - name: 'email'
    email_configs:
      - to: 'admin@example.com'
        from: 'alertmanager@example.com'
        smarthost: 'smtp.gmail.com:587'
```

## 🎯 Scaling to More Pi Zeros

**The stack automatically scales!** Simply add more Pi Zeros to your K3s cluster:

```bash
# On new Pi Zero:
curl -sfL https://get.k3s.io | K3S_URL=https://control-plane-ip:6443 \
  K3S_TOKEN=<your-token> sh -

# node-exporter DaemonSet will automatically deploy to new node
# Prometheus will auto-discover and start scraping
```

**Verify new node is monitored:**
```bash
kubectl get nodes
kubectl get pods -n monitoring -o wide
# Visit Grafana dashboard - new node appears automatically
```

## 📚 File Structure

```
manifests/observability/
├── README.md                      # This file
├── namespace.yaml                 # Monitoring namespace
├── node-exporter/
│   └── daemonset.yaml            # Host metrics collector (all nodes)
├── kube-state-metrics/
│   ├── rbac.yaml                 # K8s API permissions
│   ├── deployment.yaml           # Cluster resource metrics
│   └── service.yaml              # Headless service
├── prometheus/
│   ├── config.yaml               # Scrape configs + datasources
│   ├── rules.yaml                # Alert rules
│   ├── rbac.yaml                 # K8s API permissions
│   ├── deployment.yaml           # TSDB + scraper
│   └── service.yaml              # ClusterIP
├── alertmanager/
│   ├── config.yaml               # Alert routing
│   ├── deployment.yaml           # Alert manager
│   └── service.yaml              # ClusterIP
├── grafana/
│   ├── config.yaml               # Datasource provisioning
│   ├── dashboards-provisioning.yaml  # Dashboard auto-loading config
│   ├── dashboards-configmap.yaml     # Dashboard JSON
│   ├── deployment.yaml           # Grafana server
│   ├── service.yaml              # NodePort 32000
│   └── dashboards/
│       ├── README.md             # Dashboard customization guide
│       └── k3s-pi-cluster-monitor.json  # Custom dashboard
└── scripts/
    ├── deploy-observability.sh   # Turn-key deployment
    └── uninstall-observability.sh # Clean removal
```

## 🔐 Security Notes

**Current setup uses default credentials:**
- Grafana: admin / admin (change on first login)
- Prometheus/Alertmanager: No authentication (ClusterIP only)

**For production:**
1. Change Grafana admin password immediately
2. Configure Grafana auth (LDAP, OAuth, etc.)
3. Set up Prometheus auth via Grafana proxy
4. Configure TLS for Grafana service
5. Use Secrets instead of ConfigMaps for sensitive data

## 🤝 Contributing

Found an issue or have an improvement?
1. Test your changes on a fresh cluster
2. Update relevant documentation
3. Ensure turn-key deployment still works

## 📄 License

Free to use for personal and commercial projects.

## 🙏 Credits

Built on:
- [Prometheus](https://prometheus.io/)
- [Grafana](https://grafana.com/)
- [node_exporter](https://github.com/prometheus/node_exporter)
- [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics)
