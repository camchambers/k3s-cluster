# Custom Grafana Dashboards

This directory contains custom dashboards for your K3s Pi Zero cluster.

## Dashboard: K3s Pi Cluster Monitor

**File**: `k3s-pi-cluster-monitor.json`  
**UID**: `k3s-pi-custom`  
**URL**: http://<GRAFANA_IP>:32000/d/k3s-pi-custom/k3s-pi-cluster-monitor

### Features

- **Cluster metrics**: CPU, memory, and disk usage across all nodes
- **Pod metrics**: Top CPU/memory consuming pods
- **Node-specific**: Desktop (amd64) vs Pi Zero 2W (arm64) breakdown
- **Optimized queries**: Fixed for K3s metric names and cadvisor integration
- **Zero Angular warnings**: Uses modern Grafana panels only

### Metrics Displayed

| Panel | Metric Source | Description |
|-------|---------------|-------------|
| Current Connections | node-exporter | Active TCP connections |
| Least CPU Idle | node-exporter | Busiest node by CPU usage |
| Min Space/Memory | node-exporter | Lowest available resources |
| Pod Restarts | kube-state-metrics | Pods that have restarted recently |
| Pods Running Count | kube-state-metrics | Total running pods over time |
| Load Average | node-exporter | System load (1m, 5m, 15m) |
| Memory Usage | node-exporter | Memory consumption per node |
| CPU Idle | node-exporter | Available CPU capacity |
| Disk I/O | node-exporter | Read/write operations |
| Top 5 Memory Intense Pods | cadvisor | Pods using most memory |
| TOP CPU Containers | cadvisor | Containers using most CPU |
| Node Storage | node-exporter | Filesystem usage per node |

### Modifications Made

From the original "Kubernetes Cluster" dashboard, we fixed:

1. **Container CPU query**: Now properly filters out POD and empty containers
2. **Container memory query**: Uses cadvisor metrics with proper labels
3. **Pod restarts**: Changed to use `increase()` over 5-minute window
4. **Connections**: Uses node-level TCP stats instead of application metrics

### How to Modify

#### Option A: Edit in Grafana UI (Recommended)

1. Open dashboard: http://<GRAFANA_IP>:32000/d/k3s-pi-custom
2. Click ⚙️ Settings → Edit
3. Make your changes
4. Save dashboard
5. Export to update the JSON file:

```bash
curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "http://<GRAFANA_IP>:32000/api/dashboards/uid/k3s-pi-custom" \
  | jq '.dashboard' > manifests/observability/grafana/dashboards/k3s-pi-cluster-monitor.json
```

#### Option B: Edit JSON Directly

1. Edit `k3s-pi-cluster-monitor.json`
2. Reimport to Grafana:

```bash
jq -n --slurpfile dash manifests/observability/grafana/dashboards/k3s-pi-cluster-monitor.json '{
  dashboard: $dash[0],
  overwrite: true
}' | curl -X POST \
  -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  -d @- \
  "http://<GRAFANA_IP>:32000/api/dashboards/db"
```

### Adding New Panels

Common Prometheus queries for K3s monitoring:

```promql
# Pi Zero specific metrics
node_memory_MemAvailable_bytes{instance=~".*pi2.*"}

# Per-pod CPU usage
sum by (pod) (rate(container_cpu_usage_seconds_total{container!="POD"}[5m]))

# Per-pod memory
sum by (pod) (container_memory_working_set_bytes{container!="POD"})

# Pods by node
count by (node) (kube_pod_info)

# Namespace resource usage
sum by (namespace) (container_memory_working_set_bytes{container!="POD"})

# Network traffic
sum(rate(container_network_receive_bytes_total[5m])) by (pod)
```

### Troubleshooting

**No data in panels?**
- Wait 2-3 minutes for metrics to accumulate
- Check Prometheus targets: http://<GRAFANA_IP>:32000/datasources
- Verify scrape interval: 60s means data updates every minute

**Panel shows "N/A"?**
- Query might not match your cluster setup
- Check panel edit → Query inspector
- Test query in Prometheus UI: http://localhost:9090 (via port-forward)

**Want different time ranges?**
- Dashboard defaults to "Last 30 minutes"
- Change globally: Top-right time picker
- Change per-panel: Panel edit → Query options → Relative time

### Dashboard Provisioning

To auto-provision this dashboard on fresh Grafana deployments, add to [grafana/config.yaml](../config.yaml):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: monitoring
data:
  k3s-pi-cluster-monitor.json: |
    # paste dashboard JSON here
```

Then mount in [grafana/deployment.yaml](../deployment.yaml).
