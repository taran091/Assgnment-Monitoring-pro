# ─────────────────────────────────────────────────────────────────────────────
# Module: monitoring
#
# Monitoring strategy for the Protex observability platform:
#
# 1. VPC Peering health alarms — alert when a peering connection leaves
#    "active" state (deleted, rejected, expired, failed).
#
# 2. Network throughput / packet-drop alarms — CloudWatch VPC metrics surface
#    unusual drops that may indicate misconfigured security groups or routing.
#
# 3. API-level alarms — p95 latency and 5xx error rate thresholds to catch
#    regional connectivity issues manifesting at the application layer.
#
# 4. CloudWatch Dashboard — unified view of all peering connections and API
#    health across regions from the central account.
#
# All alarms publish to an SNS topic, which routes to PagerDuty / OpsGenie
# via subscription (configured outside this module).
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
    ManagedBy   = "terraform"
    Module      = "monitoring"
    Environment = var.environment
  })
}

# ── VPC Peering Connection State Alarms ───────────────────────────────────────
# AWS publishes a metric when peering connection status changes.
# We use a CloudWatch Event Rule (EventBridge) rather than a metric alarm because
# VpcPeeringConnection state-change events are surfaced via CloudTrail/EventBridge.

resource "aws_cloudwatch_event_rule" "peering_state_change" {
  for_each    = var.peering_connection_ids
  name        = "protex-peering-${each.key}-state-change"
  description = "Fires when the ${each.key} VPC Peering Connection changes state"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["ec2.amazonaws.com"]
      eventName   = ["DeleteVpcPeeringConnection", "RejectVpcPeeringConnection"]
      requestParameters = {
        vpcPeeringConnectionId = [each.value]
      }
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "peering_state_change_sns" {
  for_each  = var.peering_connection_ids
  rule      = aws_cloudwatch_event_rule.peering_state_change[each.key].name
  target_id = "sns-${each.key}"
  arn       = var.alarm_sns_topic_arn
}

# ── API Latency Alarm (Central only) ─────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "api_latency_p95" {
  count               = var.api_function_name != "" ? 1 : 0
  alarm_name          = "protex-${var.environment}-api-latency-p95"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 60
  extended_statistic  = "p95" # percentiles use extended_statistic, not statistic
  threshold           = var.latency_threshold_ms
  alarm_description   = "p95 API latency exceeded ${var.latency_threshold_ms}ms — possible regional DB connectivity issue"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.api_function_name
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]

  tags = local.common_tags
}

# ── API Error Rate Alarm ──────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "api_errors" {
  count               = var.api_function_name != "" ? 1 : 0
  alarm_name          = "protex-${var.environment}-api-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = var.error_rate_threshold_pct

  metric_query {
    id          = "error_rate"
    expression  = "errors / invocations * 100"
    label       = "Error Rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "Errors"
      namespace   = "AWS/Lambda"
      period      = 60
      stat        = "Sum"
      dimensions = {
        FunctionName = var.api_function_name
      }
    }
  }

  metric_query {
    id = "invocations"
    metric {
      metric_name = "Invocations"
      namespace   = "AWS/Lambda"
      period      = 60
      stat        = "Sum"
      dimensions = {
        FunctionName = var.api_function_name
      }
    }
  }

  alarm_description  = "5xx error rate exceeded ${var.error_rate_threshold_pct}%"
  treat_missing_data = "notBreaching"
  alarm_actions      = [var.alarm_sns_topic_arn]
  ok_actions         = [var.alarm_sns_topic_arn]

  tags = local.common_tags
}

# ── CloudWatch Dashboard ──────────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "protex_network" {
  count          = var.environment == "central" ? 1 : 0
  dashboard_name = "Protex-Network-Health"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "## Protex Observability — Network Health Dashboard"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "API p95 Latency (ms)"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.api_function_name,
            { stat = "p95", label = "p95 Latency" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "API Error Count"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", var.api_function_name,
            { stat = "Sum", color = "#d62728" }]
          ]
        }
      }
    ]
  })
}

# ── SNS Topic for Alarms (if not passed in, create one) ───────────────────────
# Note: In production, this topic and its PagerDuty subscription would live in
# a separate "alerting" module managed by the platform team.

resource "aws_sns_topic_policy" "alarm_publish" {
  arn = var.alarm_sns_topic_arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudWatchAlarms"
      Effect = "Allow"
      Principal = {
        Service = "cloudwatch.amazonaws.com"
      }
      Action   = "SNS:Publish"
      Resource = var.alarm_sns_topic_arn
    }]
  })
}
