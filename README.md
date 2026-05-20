# K3s Observability Stack - Prometheus + Grafana

Lightweight monitoring solution for mixed-architecture K3s cluster (AMD64 desktop + ARM64 Raspberry Pi Zero 2W).

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Desktop Node (amd64)                     │
│  ┌──────────────┐  ┌────────────┐  ┌─────────────────────┐  │
│  │  Prometheus  │  │  Grafana   │  │   Alertmanager      │  │
│  │  (Storage)   │◄─┤ (NodePort) │  │                     │  │
│  │   90d/50GB   │  │   :32000   │  │  Alert Routing      │  │
│  └──────┬───────┘  └────────────┘  └─────────────────────┘  │
│         │                                                   │
│         │ Scrapes (60s interval)                            │
│  ┌──────▼───────┐  ┌──────────────┐                         │
│  │ node-exporter│  │kube-state-   │                         │
│  │              │  │  metrics     │                         │
│  └──────────────┘  └──────────────┘                         │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ Scrapes
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Raspberry Pi Zero 2W (arm64)                   │
│  ┌──────────────┐                                           │
│  │ node-exporter│  (30Mi/50Mi memory limits)                │
│  │              │                                           │
│  └──────────────┘                                           │
└─────────────────────────────────────────────────────────────┘
```

## Components

- **Prometheus v2.51.2**: Metrics collection and storage (90 days or 50GB retention)
- **Grafana v10.4.2**: Visualization dashboards (exposed at NodePort 32000)
- **Alertmanager v0.27.0**: Alert routing and grouping
- **node-exporter v1.7.0**: Node-level metrics (CPU, memory, disk, network)
- **kube-state-metrics v2.12.0**: Cluster-level resource metrics

## Metrics Collected

### Node Metrics (via node-exporter)
- CPU usage per core and total
- Memory usage (total, available, buffers, cache)
- Disk usage and I/O statistics
- Network traffic (receive/transmit bytes, errors, drops)
- System load averages

### Cluster Metrics (via kube-state-metrics)
- Pod status and resource usage
- Deployment status and replicas
- Node status and capacity
- Persistent volume usage
- ConfigMap and Secret counts

### Container Metrics (via cAdvisor)
- Container CPU usage
- Container memory working set
- Container network traffic
- Container filesystem usage

## Alert Rules

| Alert | Threshold | Duration | Severity |
|-------|-----------|----------|----------|
| NodeDown | Node exporter unreachable | 2m | critical |
| HighMemoryUsage | Memory >85% | 5m | warning |
| CriticalMemoryUsage | Memory >95% | 2m | critical |
| HighCPUUsage | CPU >80% | 10m | warning |
| DiskSpaceLow | Root FS <15% free | 5m | warning |
| DiskSpaceCritical | Root FS <5% free | 2m | critical |
| PrometheusStorageHigh | TSDB >45GB | 5m | warning |

## Prerequisites

- K3s cluster running (control plane + worker nodes)
- kubectl configured to access the cluster
- Desktop node with:
  - `/mnt/prometheus-data` directory (will be created automatically)
  - `/mnt/grafana-data` directory (will be created automatically)
  - Label: `kubernetes.io/arch=amd64`

## Security Setup

Before deploying, create a Kubernetes Secret for the Grafana admin credentials:

```bash
kubectl create namespace monitoring  # skip if already exists

kubectl create secret generic grafana-admin-credentials \
  --namespace monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=<your-secure-password>
```

> **Note:** Replace `<your-secure-password>` with a strong password. This secret is referenced by `manifests/observability/grafana/deployment.yaml`.

## Deployment

### 1. Apply Manifests

Apply in order (dependencies matter):

```bash
# Navigate to project root
cd k3_cluster

# Apply namespace first
kubectl apply -f manifests/observability/namespace.yaml

# Apply RBAC
kubectl apply -f manifests/observability/kube-state-metrics/rbac.yaml
kubectl apply -f manifests/observability/prometheus/rbac.yaml

# Apply ConfigMaps
kubectl apply -f manifests/observability/prometheus/config.yaml
kubectl apply -f manifests/observability/prometheus/rules.yaml
kubectl apply -f manifests/observability/alertmanager/config.yaml
kubectl apply -f manifests/observability/grafana/config.yaml

# Apply workloads
kubectl apply -f manifests/observability/node-exporter/
kubectl apply -f manifests/observability/kube-state-metrics/
kubectl apply -f manifests/observability/prometheus/
kubectl apply -f manifests/observability/alertmanager/
kubectl apply -f manifests/observability/grafana/
```

Or apply everything at once:

```bash
kubectl apply -f manifests/observability/
```

### 2. Verify Deployment

Check all pods are running:

```bash
kubectl get pods -n monitoring -o wide
```

Expected output:
```
NAME                                  READY   STATUS    NODE
node-exporter-xxxxx                   1/1     Running   <control-plane-node> (desktop)
node-exporter-yyyyy                   1/1     Running   pi2 (Pi Zero)
kube-state-metrics-xxxxx              1/1     Running   <control-plane-node>
prometheus-xxxxx                      1/1     Running   <control-plane-node>
alertmanager-xxxxx                    1/1     Running   <control-plane-node>
grafana-xxxxx                         1/1     Running   <control-plane-node>
```

Check services:

```bash
kubectl get svc -n monitoring
```

### 3. Verify Prometheus Targets

Port-forward to Prometheus:

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

Open browser to http://localhost:9090/targets

All targets should show state **UP**:
- prometheus (1/1 up)
- node-exporter (2/2 up - desktop + Pi)
- kube-state-metrics (1/1 up)
- kubelet (2/2 up)
- cadvisor (2/2 up)

### 4. Access Grafana

Grafana is exposed via NodePort 32000. Access it at:

```
http://<CONTROL_PLANE_IP>:32000
```

**Default credentials** (change on first login):
- Username: `admin`
- Password: set via Kubernetes Secret (see [Security Setup](#security-setup) below)

You'll be prompted to change the password on first login.

### 5. Import Dashboards

In Grafana UI:

1. Click **"+"** (Create) → **Import**
2. Enter dashboard ID and click **Load**
3. Select **Prometheus** as the datasource
4. Click **Import**

**Recommended Dashboards:**

| Dashboard ID | Name | Description |
|--------------|------|-------------|
| **15661** | K3s Cluster Monitoring | Optimized for K3s, shows cluster overview |
| **1860** | Node Exporter Full | Comprehensive node metrics (CPU, memory, disk, network) |
| **13824** | Raspberry Pi Monitoring | ARM-specific metrics and Pi health |
| **12006** | Kubernetes API Server | API server performance |
| **315** | Kubernetes Cluster Monitoring | Simple cluster overview |

**Import via JSON (alternative):**
1. Download dashboard JSON from https://grafana.com/grafana/dashboards/[ID]
2. In Grafana: **Create** → **Import** → **Upload JSON file**

### 6. Verify Data Persistence

Check that data directories were created:

```bash
# On desktop node
ls -la /mnt/prometheus-data
ls -la /mnt/grafana-data
```

Prometheus should create TSDB blocks:
```bash
ls -la /mnt/prometheus-data/
# Should show: chunks_head/, queries.active, wal/
```

## Configuration

### Adjust Scrape Interval

Edit `manifests/observability/prometheus/config.yaml`:

```yaml
global:
  scrape_interval: 60s  # Change to 30s or 120s as needed
```

Apply changes:
```bash
kubectl apply -f manifests/observability/prometheus/config.yaml
kubectl rollout restart -n monitoring deployment/prometheus
```

### Adjust Retention

Edit `manifests/observability/prometheus/deployment.yaml`:

```yaml
args:
- '--storage.tsdb.retention.time=90d'  # Change to 60d, 180d, etc.
- '--storage.tsdb.retention.size=50GB' # Change to 100GB, etc.
```

Apply:
```bash
kubectl apply -f manifests/observability/prometheus/deployment.yaml
```

### Configure Alert Receivers

Edit `manifests/observability/alertmanager/config.yaml` to add notification channels:

**Slack Example:**
```yaml
receivers:
- name: 'critical-receiver'
  slack_configs:
  - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
    channel: '#alerts'
    title: 'K3s Cluster Alert'
    text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

**Email Example:**
```yaml
receivers:
- name: 'default-receiver'
  email_configs:
  - to: 'your-email@example.com'
    from: 'alertmanager@example.com'
    smarthost: 'smtp.example.com:587'
    auth_username: 'your-username'
    auth_password: 'your-password'
```

**Webhook Example:**
```yaml
receivers:
- name: 'default-receiver'
  webhook_configs:
  - url: 'http://your-webhook-endpoint.com/alerts'
```

Apply changes:
```bash
kubectl apply -f manifests/observability/alertmanager/config.yaml
kubectl rollout restart -n monitoring deployment/alertmanager
```

## Troubleshooting

### Prometheus Not Scraping Targets

**Check pod logs:**
```bash
kubectl logs -n monitoring -l app=prometheus
```

**Common issues:**
- RBAC permissions: Verify Prometheus ServiceAccount has ClusterRole
- Network policies: Ensure pods can communicate
- K3s endpoints: Check kubelet is accessible at `kubernetes.default.svc:443`

### Node-exporter Not Running on Pi Zero

**Check memory limits:**
```bash
kubectl describe pod -n monitoring -l app=node-exporter
```

If OOMKilled, reduce limits in `manifests/observability/node-exporter/daemonset.yaml`:
```yaml
resources:
  limits:
    memory: 40Mi  # Reduce from 50Mi
```

### Grafana Dashboards Not Loading

**Check datasource connection:**
1. In Grafana: **Configuration** → **Data Sources** → **Prometheus**
2. Click **Save & Test**
3. Should show: "Data source is working"

**If failing:**
- Verify Prometheus service DNS: `kubectl get svc -n monitoring prometheus`
- Check Prometheus is running: `kubectl get pods -n monitoring -l app=prometheus`

### High Memory on Pi Zero

**Check current usage:**
```bash
kubectl top nodes
kubectl top pods -n monitoring
```

**Reduce scrape frequency:**
Edit prometheus config to increase `scrape_interval` to 120s or 180s.

**Disable cAdvisor metrics:**
Remove the `cadvisor` scrape job from `prometheus/config.yaml` if not needed.

### Storage Full

**Check Prometheus storage:**
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Visit http://localhost:9090/tsdb-status
```

**Manually compact:**
```bash
# Exec into Prometheus pod
kubectl exec -n monitoring -it deployment/prometheus -- sh
# Trigger compaction
kill -HUP 1
```

**Reduce retention:**
Lower `storage.tsdb.retention.time` or `retention.size` in deployment.

## Monitoring Best Practices

### Dashboard Organization

1. **Overview Dashboard**: Import 15661 for cluster health at-a-glance
2. **Node Details**: Import 1860 for deep-dive into node performance
3. **Pi-Specific**: Import 13824 to monitor ARM-specific issues
4. **Custom Panels**: Create dashboard for your specific workloads

### Alert Tuning

Monitor alert frequency for 1-2 weeks, then adjust:

- **Too many alerts**: Increase thresholds or durations
- **Missing issues**: Decrease thresholds
- **Flapping**: Increase `for` duration in alert rules

### Performance Optimization

For Pi Zero stability:

1. Keep scrape_interval at 60s or higher
2. Monitor node-exporter memory usage
3. Limit cAdvisor metrics to essentials
4. Consider disabling kube-state-metrics if not needed

### Backup Strategy

Prometheus data is ephemeral by design. For important metrics:

1. Use Grafana snapshots for dashboards
2. Export queries to JSON
3. Consider Prometheus remote_write to long-term storage if needed

## Resource Usage

### Expected Memory Usage

| Component | Desktop Node | Pi Zero Node |
|-----------|--------------|--------------|
| Prometheus | 1-2 GB | - |
| Grafana | 256-512 MB | - |
| Alertmanager | 128-256 MB | - |
| kube-state-metrics | 50-100 MB | - |
| node-exporter | 30-50 MB | 30-50 MB |
| **Total** | ~2-3 GB | ~30-50 MB |

### Pi Zero Capacity

- Total RAM: 512 MB
- OS + kubelet: ~150-200 MB
- node-exporter: ~50 MB
- Your workloads: ~200-260 MB available

## K3s-Specific Notes

### Kubelet Metrics Path

K3s exposes kubelet metrics at `/api/v1/nodes/{node}/proxy/metrics` (not `/metrics/cadvisor`).

The configuration automatically uses K3s-compatible paths.

### cAdvisor Integration

K3s embeds cAdvisor in kubelet. Access via `/api/v1/nodes/{node}/proxy/metrics/cadvisor`.

Metrics are filtered to essentials to reduce load.

### API Server Access

Prometheus uses in-cluster ServiceAccount to access Kubernetes API via `kubernetes.default.svc:443`.

## Advanced: Adding Custom Metrics

To scrape application metrics:

1. **Instrument your app** with Prometheus client library
2. **Expose /metrics endpoint** in your pod
3. **Add scrape config** to `prometheus/config.yaml`:

```yaml
- job_name: 'my-app'
  kubernetes_sd_configs:
  - role: pod
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_label_app]
    action: keep
    regex: my-app-name
  - source_labels: [__meta_kubernetes_pod_container_port_number]
    action: keep
    regex: "8080"  # Your metrics port
```

## Support

For issues or questions:
- Check pod logs: `kubectl logs -n monitoring <pod-name>`
- Describe resources: `kubectl describe -n monitoring <resource>`
- Prometheus status: http://localhost:9090 (port-forward first)
- Grafana explore: http://<CONTROL_PLANE_IP>:32000/explore

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [K3s Documentation](https://docs.k3s.io/)
- [Node Exporter Metrics](https://github.com/prometheus/node_exporter)
- [Kube-state-metrics](https://github.com/kubernetes/kube-state-metrics)
