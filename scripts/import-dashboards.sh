#!/bin/bash
# Import recommended Grafana dashboards for K3s monitoring

set -e

GRAFANA_URL="${GRAFANA_URL:-http://localhost:32000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"

# Dashboard IDs to import
DASHBOARDS=(
  "15661"  # K3s Cluster Monitoring (optimized for K3s)
  "1860"   # Node Exporter Full
  "13824"  # Raspberry Pi Monitoring
)

echo "📊 Importing Grafana Dashboards..."
echo "Grafana URL: $GRAFANA_URL"
echo ""

# Wait for Grafana to be ready
echo "⏳ Waiting for Grafana to be ready..."
for i in {1..30}; do
  if curl -sf "$GRAFANA_URL/api/health" > /dev/null 2>&1; then
    echo "✅ Grafana is ready"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "❌ Timeout waiting for Grafana"
    exit 1
  fi
  sleep 2
done

echo ""

# Import each dashboard
for dashboard_id in "${DASHBOARDS[@]}"; do
  echo "📥 Importing dashboard ID: $dashboard_id..."
  
  # Use temp files to avoid "Argument list too long" error
  tmp_dashboard="/tmp/dashboard_${dashboard_id}.json"
  tmp_payload="/tmp/payload_${dashboard_id}.json"
  
  # Fetch dashboard JSON from grafana.com
  if ! curl -sf "https://grafana.com/api/dashboards/$dashboard_id/revisions/latest/download" -o "$tmp_dashboard"; then
    echo "⚠️  Failed to fetch dashboard $dashboard_id"
    rm -f "$tmp_dashboard"
    continue
  fi
  
  # Get dashboard title
  dashboard_title=$(jq -r '.title // "Unknown"' "$tmp_dashboard")
  
  # Prepare import payload
  jq -n \
    --arg datasource "Prometheus" \
    --slurpfile dashboard "$tmp_dashboard" \
    '{
      dashboard: $dashboard[0],
      overwrite: true,
      inputs: [
        {
          name: "DS_PROMETHEUS",
          type: "datasource",
          pluginId: "prometheus",
          value: $datasource
        }
      ]
    }' > "$tmp_payload"
  
  # Import to Grafana
  response=$(curl -sf -X POST \
    -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -d "@$tmp_payload" \
    "$GRAFANA_URL/api/dashboards/import" 2>&1 || echo "")
  
  if echo "$response" | grep -q "success\|imported\|uid"; then
    echo "✅ Imported: $dashboard_title"
  else
    echo "⚠️  Retrying without datasource mapping..."
    # Try without datasource mapping
    jq -n \
      --slurpfile dashboard "$tmp_dashboard" \
      '{
        dashboard: $dashboard[0],
        overwrite: true
      }' > "$tmp_payload"
    
    response=$(curl -sf -X POST \
      -H "Content-Type: application/json" \
      -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
      -d "@$tmp_payload" \
      "$GRAFANA_URL/api/dashboards/import" 2>&1 || echo "")
    
    if echo "$response" | grep -q "success\|imported\|uid"; then
      echo "✅ Imported: $dashboard_title"
    else
      echo "❌ Failed to import: $dashboard_title"
    fi
  fi
  
  # Cleanup
  rm -f "$tmp_dashboard" "$tmp_payload"
  echo ""
done

echo "🎉 Dashboard import complete!"
echo ""
echo "Access Grafana at: $GRAFANA_URL"
echo "Go to: Dashboards → Browse to see your imported dashboards"
