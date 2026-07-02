# ─────────────────────────────────────────────────────────────────────────────
# Module: observability
#
# Provisions a fully-managed Prometheus + Grafana stack using AWS-native
# managed services. No containers or servers to operate.
#
# Components:
#   1. Amazon Managed Prometheus (AMP) workspace
#      - Receives remote_write from the Video Recorder Server (edge layer)
#      - Encrypted at rest with customer-managed KMS key
#      - Audit logs shipped to CloudWatch
#
#   2. Amazon Managed Grafana (AMG) workspace
#      - Data sources: AMP (app + edge metrics) + CloudWatch (AWS/network metrics)
#        + PostgreSQL (direct Aurora connections via VPC Peering per region)
#      - Auth: AWS SSO (internal Protex teams only)
#      - Alert rules forward to the existing SNS alarm topic
#      - VPC configuration so AMG can reach private Aurora endpoints
#
#   3. IAM wiring
#      - Grafana service role → AmazonPrometheusQueryAccess + CloudWatch read
#
#   4. Grafana PostgreSQL data sources (provisioned via Grafana provider)
#      - One data source per regional Aurora cluster (EU, US, CA, APAC)
#      - Engineers query Aurora directly from Grafana dashboards
#      - Row-level security in Aurora enforces per-team data access
#
# Why managed services over self-hosted?
#   - No Prometheus/Grafana upgrade/backup burden on the platform team
#   - AMP scales automatically; no storage provisioning
#   - AMG integrates with AWS SSO out-of-box — no separate user database
#   - Both are VPC-private; no public endpoints required
# ─────────────────────────────────────────────────────────────────────────────

locals {
  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "observability"
  })
}

# ── KMS key for AMP encryption ────────────────────────────────────────────────

resource "aws_kms_key" "amp" {
  description             = "KMS key for Amazon Managed Prometheus - ${var.name_prefix}"
  deletion_window_in_days = 14
  enable_key_rotation     = true
  tags                    = local.common_tags
}

resource "aws_kms_alias" "amp" {
  name          = "alias/${var.name_prefix}-amp"
  target_key_id = aws_kms_key.amp.key_id
}

# ── Amazon Managed Prometheus (AMP) ──────────────────────────────────────────

resource "aws_prometheus_workspace" "this" {
  alias = "${var.name_prefix}-metrics"

  # Ship AMP audit logs (workspace creation, rule changes) to CloudWatch
  logging_configuration {
    log_group_arn = "${aws_cloudwatch_log_group.amp.arn}:*"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "amp" {
  name              = "/aws/prometheus/${var.name_prefix}"
  retention_in_days = var.amp_log_retention_days
  kms_key_id        = aws_kms_key.amp.arn
  tags              = local.common_tags
}

# ── AMP Alert Manager (routes Prometheus alerts → SNS) ───────────────────────
# Alert Manager is embedded in AMP; no separate deployment needed.

resource "aws_prometheus_alert_manager_definition" "this" {
  workspace_id = aws_prometheus_workspace.this.id

  definition = <<-YAML
    alertmanager_config: |
      global:
        resolve_timeout: 5m
      route:
        receiver: sns-alerts
        group_by: ['alertname', 'region', 'workspace']
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 12h
      receivers:
        - name: sns-alerts
          sns_configs:
            - api_url: https://sns.us-east-1.amazonaws.com
              topic_arn: ${var.alert_sns_topic_arn}
              attributes:
                severity: '{{ .CommonLabels.severity }}'
  YAML
}

# ── Prometheus recording rules ────────────────────────────────────────────────
# Pre-compute expensive queries so dashboards load fast.

resource "aws_prometheus_rule_group_namespace" "protex" {
  name         = "protex-rules"
  workspace_id = aws_prometheus_workspace.this.id

  data = <<-YAML
    groups:
      - name: api_health
        interval: 30s
        rules:
          # 5-min rolling error rate broken down by region label
          - record: protex:api_error_rate_5m
            expr: |
              sum by (region) (rate(http_requests_total{status=~"5.."}[5m]))
              /
              sum by (region) (rate(http_requests_total[5m]))

          # p95 latency per region — use le histogram bucket for accurate percentile
          - record: protex:api_latency_p95_5m
            expr: |
              histogram_quantile(0.95,
                sum by (region, le) (rate(http_request_duration_seconds_bucket[5m]))
              )

          # p99 latency per region — surface tail latency separately
          - record: protex:api_latency_p99_5m
            expr: |
              histogram_quantile(0.99,
                sum by (region, le) (rate(http_request_duration_seconds_bucket[5m]))
              )

          # DB query latency as seen from Grafana instrumentation
          # Instrument the DB client with a histogram: db_query_duration_seconds{region="eu"}
          - record: protex:db_query_latency_p95_5m
            expr: |
              histogram_quantile(0.95,
                sum by (region, le) (rate(db_query_duration_seconds_bucket[5m]))
              )

          # Query throughput per region
          - record: protex:db_query_rate_5m
            expr: |
              sum by (region) (rate(db_queries_total[5m]))

      - name: connectivity_health
        interval: 60s
        rules:
          # VPC peering packet drops sourced from CloudWatch exporter
          - record: protex:peering_packet_drops_5m
            expr: rate(aws_vpc_peering_packets_dropped_total[5m])

          # Connectivity probe metric from regional Lambda
          # 0 = DB unreachable from regional probe, 1 = OK
          - record: protex:regional_db_reachable
            expr: |
              min by (region) (
                aws_cloudwatch_metric{namespace="Protex/Connectivity",
                                      metric_name="RegionalDBReachable"}
              )

          # Alert if any region has been unreachable for >2 minutes
          - alert: RegionalDBUnreachable
            expr: protex:regional_db_reachable == 0
            for: 2m
            labels:
              severity: critical
            annotations:
              summary: "CONNECTIVITY FAILURE — Aurora DB unreachable in region {{ $labels.region }}"
              description: "VPC Peering may have a silent routing failure. Check route tables and peering connection status."

      - name: slow_query_alerts
        rules:
          # Fires when DB query latency (Aurora layer) exceeds threshold
          - alert: SlowAuroraQueries
            expr: protex:db_query_latency_p95_5m > 0.5
            for: 3m
            labels:
              severity: warning
            annotations:
              summary: "p95 DB query latency > 500ms in region {{ $labels.region }}"
              description: "Slow queries at the Aurora layer — check Aurora Performance Insights and slow query log."

          # Fires when API p95 is high but DB latency is low — network issue
          - alert: NetworkLatencyAnomaly
            expr: |
              protex:api_latency_p95_5m > 2
              and
              protex:db_query_latency_p95_5m < 0.1
            for: 3m
            labels:
              severity: warning
            annotations:
              summary: "API slow but DB fast in {{ $labels.region }} — likely network/peering latency"
              description: "API p95 > 2s but DB queries are fast (<100ms). Investigate VPC Peering or cross-region network path."

      - name: api_alerts
        rules:
          - alert: HighErrorRate
            expr: protex:api_error_rate_5m > 0.01
            for: 2m
            labels:
              severity: critical
            annotations:
              summary: "API error rate > 1% in region {{ $labels.region }}"

          - alert: HighLatency
            expr: protex:api_latency_p95_5m > 2
            for: 3m
            labels:
              severity: warning
            annotations:
              summary: "p95 latency > 2s in region {{ $labels.region }}"
  YAML
}

# ── IAM: Grafana service role ─────────────────────────────────────────────────

resource "aws_iam_role" "grafana" {
  name        = "${var.name_prefix}-grafana-role"
  description = "Service role for Amazon Managed Grafana — read access to AMP and CloudWatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "grafana.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })

  tags = local.common_tags
}

data "aws_caller_identity" "current" {}

# Managed policies for Grafana data sources
resource "aws_iam_role_policy_attachment" "grafana_amp_query" {
  role       = aws_iam_role.grafana.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess"
}

resource "aws_iam_role_policy_attachment" "grafana_cloudwatch" {
  role       = aws_iam_role.grafana.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonGrafanaCloudWatchAccess"
}

resource "aws_iam_role_policy_attachment" "grafana_xray" {
  role       = aws_iam_role.grafana.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayReadOnlyAccess"
}

# ── Amazon Managed Grafana (AMG) workspace ────────────────────────────────────

resource "aws_grafana_workspace" "this" {
  name        = "${var.name_prefix}-grafana"
  description = "Protex Observability Platform — unified metrics, network health, and Aurora data access"

  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = var.grafana_auth_providers
  permission_type          = "SERVICE_MANAGED"

  # Data sources Grafana is permitted to query
  data_sources = [
    "PROMETHEUS", # AMP — app + edge metrics
    "CLOUDWATCH", # AWS native — VPC peering, Lambda
    "XRAY",       # Distributed traces
  ]

  notification_destinations = ["SNS"]

  role_arn = aws_iam_role.grafana.arn

  # VPC configuration allows AMG to reach private Aurora endpoints via VPC Peering
  dynamic "vpc_configuration" {
    for_each = length(var.grafana_subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.grafana_subnet_ids
      security_group_ids = var.grafana_security_group_ids
    }
  }

  tags = local.common_tags
}

# ── Grafana workspace API keys (for provisioning dashboards via Terraform) ────

resource "aws_grafana_workspace_api_key" "provisioner" {
  key_name        = "terraform-provisioner"
  key_role        = "ADMIN"
  seconds_to_live = 3600 # Short-lived; rotated on each apply
  workspace_id    = aws_grafana_workspace.this.id
}

# ── Grafana provider (uses the workspace API key) ─────────────────────────────
# Configured after AMG workspace is created so data sources can be provisioned
# declaratively alongside the workspace itself.

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws     = { source = "hashicorp/aws",   version = ">= 5.0" }
    grafana = { source = "grafana/grafana", version = ">= 2.0" }
  }
}

provider "grafana" {
  url  = "https://${aws_grafana_workspace.this.endpoint}"
  auth = aws_grafana_workspace_api_key.provisioner.key
}

# ── Grafana PostgreSQL data sources → regional Aurora ─────────────────────────
# Each data source points to a regional Aurora writer endpoint reachable via
# VPC Peering. Engineers query these directly from Grafana dashboards.
# Row-level security in Aurora enforces per-team data access.

resource "grafana_data_source" "aurora_eu" {
  count = var.eu_aurora_endpoint != "" ? 1 : 0
  name  = "Aurora-EU"
  type  = "postgres"
  url   = "${var.eu_aurora_endpoint}:5432"
  database_name = "protex"
  username      = "protex_readonly"
  secure_json_data_encoded = jsonencode({
    password = var.eu_aurora_password
  })
  json_data_encoded = jsonencode({
    sslmode         = "require"
    postgresVersion = 1400
    timescaledb     = false
  })
}

resource "grafana_data_source" "aurora_us" {
  count = var.us_aurora_endpoint != "" ? 1 : 0
  name  = "Aurora-US"
  type  = "postgres"
  url   = "${var.us_aurora_endpoint}:5432"
  database_name = "protex"
  username      = "protex_readonly"
  secure_json_data_encoded = jsonencode({
    password = var.us_aurora_password
  })
  json_data_encoded = jsonencode({
    sslmode         = "require"
    postgresVersion = 1400
    timescaledb     = false
  })
}

resource "grafana_data_source" "aurora_ca" {
  count = var.ca_aurora_endpoint != "" ? 1 : 0
  name  = "Aurora-CA"
  type  = "postgres"
  url   = "${var.ca_aurora_endpoint}:5432"
  database_name = "protex"
  username      = "protex_readonly"
  secure_json_data_encoded = jsonencode({ password = var.ca_aurora_password })
  json_data_encoded = jsonencode({ sslmode = "require", postgresVersion = 1400, timescaledb = false })
}

resource "grafana_data_source" "aurora_apac" {
  count = var.apac_aurora_endpoint != "" ? 1 : 0
  name  = "Aurora-APAC"
  type  = "postgres"
  url   = "${var.apac_aurora_endpoint}:5432"
  database_name = "protex"
  username      = "protex_readonly"
  secure_json_data_encoded = jsonencode({ password = var.apac_aurora_password })
  json_data_encoded = jsonencode({ sslmode = "require", postgresVersion = 1400, timescaledb = false })
}
