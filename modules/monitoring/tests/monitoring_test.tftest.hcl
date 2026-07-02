# ─────────────────────────────────────────────────────────────────────────────
# Module: monitoring — Unit Tests
#
# Run with:  cd modules/monitoring && terraform test
# ─────────────────────────────────────────────────────────────────────────────

mock_provider "aws" {
  mock_resource "aws_cloudwatch_metric_alarm" {
    defaults = {
      id  = "mock-alarm-id"
      arn = "arn:aws:cloudwatch:us-east-1:111111111111:alarm:mock-alarm"
    }
  }

  mock_resource "aws_cloudwatch_event_rule" {
    defaults = {
      id  = "mock-event-rule"
      arn = "arn:aws:events:us-east-1:111111111111:rule/mock-event-rule"
    }
  }

  mock_resource "aws_cloudwatch_event_target" {
    defaults = { id = "mock-event-target" }
  }

  mock_resource "aws_cloudwatch_dashboard" {
    defaults = { id = "mock-dashboard" }
  }

  mock_resource "aws_sns_topic_policy" {
    defaults = { id = "arn:aws:sns:us-east-1:111111111111:mock-topic" }
  }
}

# ── Test 1: API alarms only created when api_function_name is provided ────────

run "api_alarms_created_for_central" {
  command = plan

  variables {
    environment              = "prod-central"
    alarm_sns_topic_arn      = "arn:aws:sns:us-east-1:111111111111:protex-prod-network-alarms"
    api_function_name        = "protex-prod-observability-api"
    latency_threshold_ms     = 2000
    error_rate_threshold_pct = 1
    peering_connection_ids   = {}
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.api_latency_p95) == 1
    error_message = "p95 latency alarm must be created when api_function_name is provided"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.api_errors) == 1
    error_message = "Error rate alarm must be created when api_function_name is provided"
  }
}

# ── Test 2: Alarms not created without api_function_name (regional modules) ──

run "no_api_alarms_for_regional" {
  command = plan

  variables {
    environment              = "prod-eu"
    alarm_sns_topic_arn      = "arn:aws:sns:us-east-1:111111111111:protex-prod-network-alarms"
    api_function_name        = ""
    latency_threshold_ms     = 2000
    error_rate_threshold_pct = 1
    peering_connection_ids   = {}
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.api_latency_p95) == 0
    error_message = "No API alarms should be created for regional environments (no API function)"
  }
}

# ── Test 3: EventBridge rule created per peering connection ──────────────────

run "eventbridge_rule_per_peering_connection" {
  command = plan

  variables {
    environment              = "prod-central"
    alarm_sns_topic_arn      = "arn:aws:sns:us-east-1:111111111111:protex-prod-network-alarms"
    api_function_name        = "protex-prod-observability-api"
    latency_threshold_ms     = 2000
    error_rate_threshold_pct = 1
    peering_connection_ids = {
      eu   = "pcx-eu-mock"
      us   = "pcx-us-mock"
      ca   = "pcx-ca-mock"
      apac = "pcx-apac-mock"
    }
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.peering_state_change) == 4
    error_message = "One EventBridge rule must be created per peering connection (4 regions = 4 rules)"
  }
}

# ── Test 4: prod latency threshold tighter than dev ──────────────────────────
# Validates that the workspace-tuned threshold value actually flows into the alarm.

run "prod_latency_threshold_is_strict" {
  command = plan

  variables {
    environment              = "prod-central"
    alarm_sns_topic_arn      = "arn:aws:sns:us-east-1:111111111111:protex-prod-network-alarms"
    api_function_name        = "protex-prod-observability-api"
    latency_threshold_ms     = 2000 # prod threshold
    error_rate_threshold_pct = 1
    peering_connection_ids   = {}
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.api_latency_p95[0].threshold == 2000
    error_message = "Prod latency alarm threshold must be 2000ms as configured"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.api_latency_p95[0].extended_statistic == "p95"
    error_message = "Latency alarm must use extended_statistic p95 (not statistic)"
  }
}
