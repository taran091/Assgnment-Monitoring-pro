#!/bin/bash
# Pushes a heartbeat timestamp metric to Prometheus Pushgateway.
# Runs every 30 seconds via systemd. If device loses power or crashes,
# the metric goes stale and triggers EdgeDeviceOffline alert.

DEVICE_ID="${HOSTNAME}"
WAREHOUSE_ID="${WAREHOUSE_ID:-unknown}"
PUSHGATEWAY="${PUSHGATEWAY_URL:-http://localhost:9091}"

while true; do
  NOW=$(date +%s)
  cat <<METRICS | curl -s --data-binary @- "${PUSHGATEWAY}/metrics/job/protex_heartbeat/device_id/${DEVICE_ID}/warehouse_id/${WAREHOUSE_ID}"
# TYPE protex_device_heartbeat_timestamp_seconds gauge
protex_device_heartbeat_timestamp_seconds ${NOW}
METRICS
  sleep 30
done
