# ─────────────────────────────────────────────────────────────────────────────
# Module: regional_monitoring
#
# Deployed to EACH regional account. Monitors Aurora health and network
# connectivity from the regional side.
#
# Three layers of observability:
#
#   1. Aurora CloudWatch Alarms
#      - DatabaseConnections    → connection pool exhaustion (max ~1000 for Aurora)
#      - SelectLatency          → slow queries at the DB layer (not just API layer)
#      - AuroraReplicaLag       → read replica falling behind writer
#      - CPUUtilization         → DB under resource pressure
#
#   2. Connectivity Probe Lambda (runs every 1 minute)
#      A Python Lambda in the regional account attempts a TCP connection to the
#      Aurora writer endpoint on port 5432. It publishes a custom CloudWatch
#      metric: Protex/Connectivity — RegionalDBReachable (1=OK, 0=FAIL).
#      This catches silent routing failures that VPC Peering "active" status
#      won't surface — e.g. a missing route table entry silently drops packets.
#
#   3. CloudWatch Alarm on probe metric
#      Fires within 2 minutes of a connectivity failure → SNS → PagerDuty P1.
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
    Module    = "regional_monitoring"
    Region    = var.region
  })
}

# ── 1. Aurora CloudWatch Alarms ───────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "db_connections" {
  alarm_name          = "${var.name_prefix}-db-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.max_connections_threshold
  alarm_description   = "[${var.region}] Aurora connection count > ${var.max_connections_threshold} — risk of connection pool exhaustion"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.aurora_cluster_identifier
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
  tags          = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "select_latency" {
  alarm_name          = "${var.name_prefix}-select-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "SelectLatency"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.select_latency_threshold_ms / 1000.0  # metric is in seconds
  alarm_description   = "[${var.region}] Aurora SELECT latency > ${var.select_latency_threshold_ms}ms — slow queries at the DB layer"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.aurora_cluster_identifier
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
  tags          = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "replica_lag" {
  alarm_name          = "${var.name_prefix}-replica-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AuroraReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.replica_lag_threshold_seconds * 1000  # metric is in ms
  alarm_description   = "[${var.region}] Aurora replica lag > ${var.replica_lag_threshold_seconds}s — read replicas falling behind"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.aurora_cluster_identifier
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
  tags          = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name          = "${var.name_prefix}-db-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "[${var.region}] Aurora CPU > 80% for 15 minutes — DB under resource pressure"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.aurora_cluster_identifier
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
  tags          = local.common_tags
}

# ── 2. Connectivity Probe Lambda ──────────────────────────────────────────────
# Runs every minute inside the regional VPC private subnet.
# Attempts TCP connect to Aurora writer endpoint on port 5432.
# Publishes Protex/Connectivity::RegionalDBReachable = 1 (OK) or 0 (FAIL).
# This catches silent routing failures that "peering active" status won't catch.

resource "aws_iam_role" "probe" {
  name = "${var.name_prefix}-connectivity-probe-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "probe_vpc" {
  role       = aws_iam_role.probe.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "probe_cloudwatch" {
  name = "${var.name_prefix}-probe-cw-policy"
  role = aws_iam_role.probe.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["cloudwatch:PutMetricData"]
      Resource = "*"
      Condition = {
        StringEquals = {
          "cloudwatch:namespace" = "Protex/Connectivity"
        }
      }
    }]
  })
}

# Lambda code inline — Python TCP probe
resource "aws_lambda_function" "probe" {
  function_name = "${var.name_prefix}-connectivity-probe"
  role          = aws_iam_role.probe.arn
  runtime       = "python3.12"
  handler       = "index.handler"
  timeout       = 10

  environment {
    variables = {
      DB_HOST   = var.aurora_db_endpoint
      DB_PORT   = tostring(var.aurora_db_port)
      REGION    = var.region
      NAMESPACE = "Protex/Connectivity"
    }
  }

  filename         = data.archive_file.probe_code.output_path
  source_code_hash = data.archive_file.probe_code.output_base64sha256

  tags = local.common_tags
}

data "archive_file" "probe_code" {
  type        = "zip"
  output_path = "/tmp/protex-probe-${var.region}.zip"

  source {
    filename = "index.py"
    content  = <<-PYTHON
import socket
import boto3
import os

def handler(event, context):
    host = os.environ['DB_HOST']
    port = int(os.environ['DB_PORT'])
    region = os.environ['REGION']
    namespace = os.environ['NAMESPACE']
    reachable = 0

    try:
        sock = socket.create_connection((host, port), timeout=5)
        sock.close()
        reachable = 1
        print(f"[OK] {host}:{port} is reachable")
    except Exception as e:
        print(f"[FAIL] {host}:{port} — {e}")

    boto3.client('cloudwatch').put_metric_data(
        Namespace=namespace,
        MetricData=[{
            'MetricName': 'RegionalDBReachable',
            'Dimensions': [
                {'Name': 'Region', 'Value': region},
                {'Name': 'Endpoint', 'Value': host},
            ],
            'Value': reachable,
            'Unit': 'None'
        }]
    )
    return {'reachable': reachable}
    PYTHON
  }
}

# EventBridge schedule — fires every minute
resource "aws_cloudwatch_event_rule" "probe_schedule" {
  name                = "${var.name_prefix}-probe-schedule"
  description         = "Triggers connectivity probe for ${var.region} Aurora endpoint"
  schedule_expression = var.probe_schedule
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "probe" {
  rule      = aws_cloudwatch_event_rule.probe_schedule.name
  target_id = "connectivity-probe"
  arn       = aws_lambda_function.probe.arn
}

resource "aws_lambda_permission" "probe_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.probe.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.probe_schedule.arn
}

# ── 3. Alarm on connectivity probe metric ─────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "db_reachable" {
  alarm_name          = "${var.name_prefix}-db-reachable"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2   # fires after 2 consecutive failures (2 minutes)
  metric_name         = "RegionalDBReachable"
  namespace           = "Protex/Connectivity"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "[${var.region}] CONNECTIVITY FAILURE — Aurora DB unreachable from probe Lambda. VPC Peering may have silent routing failure."
  treat_missing_data  = "breaching"  # if probe stops running, treat as outage

  dimensions = {
    Region   = var.region
    Endpoint = var.aurora_db_endpoint
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
  tags          = local.common_tags
}
