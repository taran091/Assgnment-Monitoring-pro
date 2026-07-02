# ─────────────────────────────────────────────────────────────────────────────
# Module: regional_monitoring — Unit Tests
#
# Run with:  cd modules/regional_monitoring && terraform test
#
# Covers three monitoring layers:
#   1. Aurora CloudWatch alarms (DB connections, SELECT latency, replica lag, CPU)
#   2. Connectivity probe Lambda (deployed in regional VPC, runs every minute)
#   3. CloudWatch alarm on probe metric (silent routing failure detection)
# ─────────────────────────────────────────────────────────────────────────────

mock_provider "aws" {
  mock_resource "aws_cloudwatch_metric_alarm" {
    defaults = {
      id  = "mock-alarm"
      arn = "arn:aws:cloudwatch:eu-west-1:222222222222:alarm:mock-alarm"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      id   = "mock-probe-role"
      arn  = "arn:aws:iam::222222222222:role/mock-probe-role"
      name = "mock-probe-role"
    }
  }

  mock_resource "aws_iam_role_policy_attachment" {
    defaults = { id = "mock-probe-role/arn:aws:iam::aws:policy/AWSLambdaVPCAccessExecutionRole" }
  }

  mock_resource "aws_iam_role_policy" {
    defaults = { id = "mock-probe-role:mock-probe-cw-policy" }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      id            = "mock-probe-lambda"
      arn           = "arn:aws:lambda:eu-west-1:222222222222:function:mock-probe"
      function_name = "mock-probe"
    }
  }

  mock_resource "aws_cloudwatch_event_rule" {
    defaults = {
      id  = "mock-event-rule"
      arn = "arn:aws:events:eu-west-1:222222222222:rule/mock-event-rule"
    }
  }

  mock_resource "aws_cloudwatch_event_target" {
    defaults = { id = "mock-event-rule/connectivity-probe" }
  }

  mock_resource "aws_lambda_permission" {
    defaults = { id = "mock-probe/AllowEventBridgeInvoke" }
  }
}

# ── Test 1: All four Aurora CloudWatch alarms are created ─────────────────────

run "aurora_alarms_all_created" {
  command = plan

  variables {
    name_prefix               = "protex-prod-eu"
    region                    = "eu"
    alarm_sns_topic_arn       = "arn:aws:sns:eu-west-1:111111111112:protex-prod-network-alarms"
    aurora_cluster_identifier = "protex-prod-eu-aurora-cluster"
    aurora_db_endpoint        = "protex-prod-eu-aurora-cluster.cluster-xxxx.eu-west-1.rds.amazonaws.com"
    aurora_db_port            = 5432
    max_connections_threshold     = 800
    select_latency_threshold_ms   = 200
    replica_lag_threshold_seconds = 30
    probe_schedule                = "rate(1 minute)"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.db_connections.metric_name == "DatabaseConnections"
    error_message = "DatabaseConnections alarm must be created"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.select_latency.metric_name == "SelectLatency"
    error_message = "SelectLatency alarm must be created — detects slow queries at Aurora layer"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.replica_lag.metric_name == "AuroraReplicaLag"
    error_message = "AuroraReplicaLag alarm must be created"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.db_cpu.metric_name == "CPUUtilization"
    error_message = "CPUUtilization alarm must be created"
  }
}

# ── Test 2: Connection threshold flows through correctly ──────────────────────

run "connection_threshold_value" {
  command = plan

  variables {
    name_prefix               = "protex-prod-us"
    region                    = "us"
    alarm_sns_topic_arn       = "arn:aws:sns:eu-west-1:111111111112:protex-prod-network-alarms"
    aurora_cluster_identifier = "protex-prod-us-aurora-cluster"
    aurora_db_endpoint        = "protex-prod-us-aurora-cluster.cluster-xxxx.us-west-2.rds.amazonaws.com"
    aurora_db_port            = 5432
    max_connections_threshold     = 800
    select_latency_threshold_ms   = 200
    replica_lag_threshold_seconds = 30
    probe_schedule                = "rate(1 minute)"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.db_connections.threshold == 800
    error_message = "max_connections_threshold must flow through to alarm threshold"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.db_connections.metric_name == "DatabaseConnections"
    error_message = "Alarm must monitor DatabaseConnections metric"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.db_connections.namespace == "AWS/RDS"
    error_message = "Alarm must use AWS/RDS namespace"
  }
}

# ── Test 3: Connectivity probe Lambda is created ──────────────────────────────
# The probe runs every minute inside the regional VPC and attempts TCP connect
# to the Aurora writer endpoint — catches silent routing failures that VPC
# Peering "active" status won't surface.

run "connectivity_probe_lambda_created" {
  command = plan

  variables {
    name_prefix               = "protex-prod-eu"
    region                    = "eu"
    alarm_sns_topic_arn       = "arn:aws:sns:eu-west-1:111111111112:protex-prod-network-alarms"
    aurora_cluster_identifier = "protex-prod-eu-aurora-cluster"
    aurora_db_endpoint        = "protex-prod-eu-aurora-cluster.cluster-xxxx.eu-west-1.rds.amazonaws.com"
    aurora_db_port            = 5432
    max_connections_threshold     = 800
    select_latency_threshold_ms   = 200
    replica_lag_threshold_seconds = 30
    probe_schedule                = "rate(1 minute)"
  }

  assert {
    condition     = aws_lambda_function.probe.function_name != ""
    error_message = "Connectivity probe Lambda must be created"
  }

  assert {
    condition     = aws_lambda_function.probe.runtime == "python3.12"
    error_message = "Probe must use Python 3.12 runtime"
  }

  assert {
    condition     = aws_lambda_function.probe.timeout == 10
    error_message = "Probe timeout must be 10s (enough for TCP connect attempt)"
  }
}

# ── Test 4: EventBridge schedule wired to Lambda ──────────────────────────────
# Without this wiring, the probe never runs and we lose silent failure detection.

run "eventbridge_schedule_wired" {
  command = plan

  variables {
    name_prefix               = "protex-prod-ca"
    region                    = "ca"
    alarm_sns_topic_arn       = "arn:aws:sns:eu-west-1:111111111112:protex-prod-network-alarms"
    aurora_cluster_identifier = "protex-prod-ca-aurora-cluster"
    aurora_db_endpoint        = "protex-prod-ca-aurora-cluster.cluster-xxxx.ca-central-1.rds.amazonaws.com"
    aurora_db_port            = 5432
    max_connections_threshold     = 800
    select_latency_threshold_ms   = 200
    replica_lag_threshold_seconds = 30
    probe_schedule                = "rate(1 minute)"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.probe_schedule.schedule_expression == "rate(1 minute)"
    error_message = "EventBridge rule must fire every 1 minute"
  }

  assert {
    condition     = aws_cloudwatch_event_target.probe.target_id == "connectivity-probe"
    error_message = "EventBridge must target the probe Lambda"
  }

  assert {
    condition     = aws_lambda_permission.probe_eventbridge.action == "lambda:InvokeFunction"
    error_message = "Lambda permission must allow EventBridge invocation"
  }
}

# ── Test 5: Connectivity alarm treats missing data as breaching ───────────────
# CRITICAL: if the probe Lambda stops running (e.g. VPC routing issue),
# missing metric data must be treated as an outage — not as healthy.
# treat_missing_data = "breaching" ensures we alert on probe failures.

run "connectivity_alarm_missing_data_is_breaching" {
  command = plan

  variables {
    name_prefix               = "protex-prod-apac"
    region                    = "apac"
    alarm_sns_topic_arn       = "arn:aws:sns:eu-west-1:111111111112:protex-prod-network-alarms"
    aurora_cluster_identifier = "protex-prod-apac-aurora-cluster"
    aurora_db_endpoint        = "protex-prod-apac-aurora-cluster.cluster-xxxx.ap-southeast-1.rds.amazonaws.com"
    aurora_db_port            = 5432
    max_connections_threshold     = 800
    select_latency_threshold_ms   = 200
    replica_lag_threshold_seconds = 30
    probe_schedule                = "rate(1 minute)"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.db_reachable.treat_missing_data == "breaching"
    error_message = "Missing probe metric must be treated as outage — probe failure = connectivity unknown = alert"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.db_reachable.evaluation_periods == 2
    error_message = "Alarm must fire after 2 consecutive failures (2 minutes) to avoid transient false positives"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.db_reachable.metric_name == "RegionalDBReachable"
    error_message = "Alarm must monitor the Protex/Connectivity::RegionalDBReachable custom metric"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.db_reachable.namespace == "Protex/Connectivity"
    error_message = "Alarm must use Protex/Connectivity namespace"
  }
}

# ── Test 6: Alarm name includes region for easy identification ────────────────

run "alarm_names_include_region" {
  command = plan

  variables {
    name_prefix               = "protex-prod-eu"
    region                    = "eu"
    alarm_sns_topic_arn       = "arn:aws:sns:eu-west-1:111111111112:protex-prod-network-alarms"
    aurora_cluster_identifier = "protex-prod-eu-aurora-cluster"
    aurora_db_endpoint        = "protex-prod-eu-aurora-cluster.cluster-xxxx.eu-west-1.rds.amazonaws.com"
    aurora_db_port            = 5432
    max_connections_threshold     = 800
    select_latency_threshold_ms   = 200
    replica_lag_threshold_seconds = 30
    probe_schedule                = "rate(1 minute)"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.db_reachable.alarm_name == "protex-prod-eu-db-reachable"
    error_message = "Connectivity alarm name must include region prefix for easy identification in CloudWatch"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.db_connections.alarm_name == "protex-prod-eu-db-connections"
    error_message = "Connection alarm name must include region prefix"
  }
}
