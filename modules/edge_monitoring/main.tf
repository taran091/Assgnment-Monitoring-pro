# ─────────────────────────────────────────────────────────────────────────────
# Module: edge_monitoring
#
# Monitors Protex Linux-based edge devices deployed in warehouses.
#
# Architecture:
#   Edge Device (Linux)
#     ├── Node Exporter (port 9100)       → system metrics (CPU, mem, disk, net)
#     ├── Protex App Exporter (port 9200) → inference metrics, event throughput
#     └── Heartbeat timer (systemd)       → protex_device_heartbeat_seconds_total
#          |
#          ↓ (local warehouse network)
#   Video Recorder Server
#     └── Prometheus (scrapes all devices in warehouse)
#          └── remote_write → AMP (via outbound HTTPS)
#                └── Grafana → dashboards + alerts
#
# Key signals monitored:
#   1. Device liveness (heartbeat missing > 5 min = device offline)
#   2. AI inference health (error rate, latency)
#   3. Video buffer disk space (fills up → events stop)
#   4. CPU/memory under inference load
#   5. Event throughput (events/sec per device)
#   6. MQTT connectivity (events reaching the broker)
#
# This module manages the AMP recording rules and alert rules only.
# Node Exporter and Prometheus are deployed to edge devices via Ansible
# (see config/prometheous-ansible/ for playbooks — outside Terraform scope).
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "edge_monitoring"
  })
}

# ── AMP Recording Rules for Edge Device Fleet ─────────────────────────────────
# Pre-compute expensive fleet-wide aggregations so Grafana dashboards
# are fast regardless of fleet size.

resource "aws_prometheus_rule_group_namespace" "edge_devices" {
  name         = "protex-edge-devices"
  workspace_id = var.amp_workspace_id

  data = <<-YAML
    groups:
      # ── Device Liveness ───────────────────────────────────────────────────────
      - name: device_liveness
        interval: 30s
        rules:
          # Seconds since last heartbeat per device.
          # Devices push protex_device_heartbeat_total (counter) every 30s via
          # a systemd timer. If the counter stops incrementing, the device is offline.
          - record: protex:device_seconds_since_heartbeat
            expr: |
              time() - max by (device_id, warehouse_id, region) (
                protex_device_heartbeat_timestamp_seconds
              )

          # Fleet summary: how many devices are currently offline per region
          - record: protex:devices_offline_count
            expr: |
              count by (region) (
                protex:device_seconds_since_heartbeat > ${var.device_offline_threshold_minutes * 60}
              ) or vector(0)

          # Alert: device has not sent a heartbeat within threshold
          - alert: EdgeDeviceOffline
            expr: |
              protex:device_seconds_since_heartbeat
              > ${var.device_offline_threshold_minutes * 60}
            for: 1m
            labels:
              severity: critical
              layer: edge
            annotations:
              summary: "Edge device {{ $labels.device_id }} offline in {{ $labels.warehouse_id }}"
              description: >
                Device has not sent a heartbeat for
                {{ $value | humanizeDuration }}. Check device power,
                network connectivity, and Protex service status.

      # ── AI Inference Health ───────────────────────────────────────────────────
      - name: inference_health
        interval: 30s
        rules:
          # p95 inference latency per device (Histogram from Protex app exporter)
          - record: protex:inference_latency_p95_5m
            expr: |
              histogram_quantile(0.95,
                sum by (device_id, warehouse_id, le) (
                  rate(protex_inference_duration_seconds_bucket[5m])
                )
              )

          # Inference error rate per device
          - record: protex:inference_error_rate_1m
            expr: |
              sum by (device_id, warehouse_id) (
                rate(protex_inference_errors_total[1m])
              )

          # Alert: inference errors spiking (AI model or hardware issue)
          - alert: InferenceErrorRateHigh
            expr: |
              protex:inference_error_rate_1m > ${var.inference_error_threshold}
            for: 2m
            labels:
              severity: warning
              layer: edge
            annotations:
              summary: "High inference error rate on {{ $labels.device_id }}"
              description: >
                {{ $value | humanize }} inference errors/min on device
                {{ $labels.device_id }} in {{ $labels.warehouse_id }}.
                Check AI model logs and GPU/CPU health.

      # ── System Resources ──────────────────────────────────────────────────────
      - name: system_resources
        interval: 60s
        rules:
          # CPU usage per device (from Node Exporter)
          - record: protex:device_cpu_usage_pct
            expr: |
              100 - (
                avg by (device_id, warehouse_id) (
                  rate(node_cpu_seconds_total{mode="idle"}[5m])
                ) * 100
              )

          # Video buffer disk free space in GB
          - record: protex:device_disk_free_gb
            expr: |
              min by (device_id, warehouse_id, mountpoint) (
                node_filesystem_avail_bytes{mountpoint="/var/protex/video"}
              ) / 1024 / 1024 / 1024

          # Alert: CPU sustained high (inference under load, thermal throttling)
          - alert: EdgeDeviceCPUHigh
            expr: protex:device_cpu_usage_pct > ${var.cpu_threshold_pct}
            for: 5m
            labels:
              severity: warning
              layer: edge
            annotations:
              summary: "CPU > ${var.cpu_threshold_pct}% on {{ $labels.device_id }}"
              description: >
                Edge device {{ $labels.device_id }} CPU at {{ $value | humanize }}%.
                AI inference may be throttled. Check thermal status.

          # Alert: video buffer nearly full (events will stop being captured)
          - alert: EdgeDeviceDiskLow
            expr: |
              protex:device_disk_free_gb < ${var.disk_free_threshold_gb}
            for: 2m
            labels:
              severity: critical
              layer: edge
            annotations:
              summary: "Disk critically low on {{ $labels.device_id }}"
              description: >
                Only {{ $value | humanize }}GB free on video buffer partition of
                {{ $labels.device_id }}. Events will stop being captured when disk is full.
                Trigger immediate upstream sync or clear old video files.

      # ── Event Throughput ──────────────────────────────────────────────────────
      - name: event_throughput
        interval: 30s
        rules:
          # Events generated per device per second
          - record: protex:device_events_per_second
            expr: |
              sum by (device_id, warehouse_id, region) (
                rate(protex_events_generated_total[5m])
              )

          # Events successfully sent to MQTT broker per device
          - record: protex:device_events_sent_per_second
            expr: |
              sum by (device_id, warehouse_id, region) (
                rate(protex_events_sent_total[5m])
              )

          # MQTT send failure rate — events generated but not delivered
          - record: protex:device_mqtt_failure_rate
            expr: |
              protex:device_events_per_second
              - protex:device_events_sent_per_second

          # Alert: device generating events but none reaching MQTT
          # (MQTT broker down, network partition, credentials expired)
          - alert: EdgeDeviceMQTTFailure
            expr: |
              protex:device_mqtt_failure_rate > 0
              and protex:device_events_per_second > 0
            for: 3m
            labels:
              severity: critical
              layer: edge
            annotations:
              summary: "MQTT delivery failure on {{ $labels.device_id }}"
              description: >
                Device {{ $labels.device_id }} is detecting events but failing to
                deliver them to the MQTT broker. Events are being lost. Check MQTT
                broker connectivity and credentials.
  YAML
}

# ── CloudWatch Alarm: Fleet-level offline device count ────────────────────────
# CW can query AMP metrics via Metrics Insights.
# Fires if any region has more than 0 offline devices for 5 minutes.

resource "aws_cloudwatch_metric_alarm" "devices_offline" {
  alarm_name          = "${var.name_prefix}-edge-devices-offline"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  alarm_description   = "One or more edge devices have gone offline — check warehouse connectivity"
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "offline"
    expression  = "SELECT COUNT(protex_device_seconds_since_heartbeat) FROM SCHEMA(\"Protex/Edge\") WHERE status = 'offline'"
    label       = "Offline Device Count"
    return_data = true
    period      = 300
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
  tags          = local.common_tags
}
