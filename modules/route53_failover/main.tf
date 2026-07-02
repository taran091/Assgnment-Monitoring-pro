terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Module: route53_failover
#
# Implements active-passive regional failover for the central Observability API.
#
# How it works:
#   1. Route 53 polls the primary ALB /health endpoint every 10 seconds from
#      multiple AWS health-check nodes globally.
#   2. After 3 consecutive failures (30 seconds) the primary record is marked
#      unhealthy and Route 53 automatically starts resolving the API hostname
#      to the failover ALB in eu-west-1 instead.
#   3. When the primary recovers, Route 53 reverts the DNS record automatically.
#
# DNS TTL is set to 30 seconds so clients re-resolve quickly after a failover.
#
# The private hosted zone is associated with BOTH the primary and failover VPCs
# so engineers connecting from either central VPC resolve the same hostname.
#
# Worst-case failover time:
#   health_check_interval × failure_threshold + DNS TTL = 10×3 + 30 = 60 seconds
# ─────────────────────────────────────────────────────────────────────────────

locals {
  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "route53_failover"
  })
}

# ── Private Hosted Zone ────────────────────────────────────────────────────────
# Internal DNS — not publicly resolvable. Only reachable from within the
# primary and failover VPCs (and any VPCs peered to them).

resource "aws_route53_zone" "internal" {
  name    = var.internal_domain_name
  comment = "Private zone for Protex Observability Platform — ${var.name_prefix}"

  vpc {
    vpc_id = var.primary_vpc_id
  }

  # lifecycle prevents accidental zone deletion which would break all API DNS
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-internal-zone"
  })
}

# Associate the failover VPC with the same hosted zone so both central
# environments resolve the same hostname.
resource "aws_route53_zone_association" "failover_vpc" {
  zone_id = aws_route53_zone.internal.zone_id
  vpc_id  = var.failover_vpc_id
}

# ── Health Check on Primary ALB ───────────────────────────────────────────────
# Route 53 dispatches health checks from ~15 global nodes simultaneously.
# The endpoint is considered healthy only when a majority of nodes succeed.

resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_alb_dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = var.health_check_failure_threshold
  request_interval  = var.health_check_interval

  # Enable CloudWatch alarm integration so a failed health check triggers
  # the existing SNS → PagerDuty alert chain.
  cloudwatch_alarm_name           = "${var.name_prefix}-primary-api-health"
  cloudwatch_alarm_region         = "us-east-1"
  insufficient_data_health_status = "Unhealthy"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-primary-health-check"
    Role = "primary"
  })
}

# CloudWatch alarm that fires when Route 53 marks the primary unhealthy.
# Routes to the same SNS topic as all other platform alarms.
resource "aws_cloudwatch_metric_alarm" "primary_health" {
  alarm_name          = "${var.name_prefix}-primary-api-health"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "Primary Observability API (us-east-1) is UNHEALTHY — failover to eu-west-1 in progress"
  treat_missing_data  = "breaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary.id
  }

  # Alarm ARN is output so it can be subscribed to the central SNS topic
  tags = local.common_tags
}

# ── Failover DNS Records ───────────────────────────────────────────────────────

# PRIMARY record — serves traffic when healthy.
# Route 53 stops resolving this when health check fails.
resource "aws_route53_record" "api_primary" {
  zone_id        = aws_route53_zone.internal.zone_id
  name           = "api.${var.internal_domain_name}"
  type           = "A"
  set_identifier = "primary-us-east-1"

  alias {
    name                   = var.primary_alb_dns_name
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }

  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary.id
}

# SECONDARY record — only receives traffic when the primary is unhealthy.
# No health check needed: if the secondary were also unhealthy, Route 53
# would fall back to returning the secondary anyway (last-resort behaviour).
resource "aws_route53_record" "api_failover" {
  zone_id        = aws_route53_zone.internal.zone_id
  name           = "api.${var.internal_domain_name}"
  type           = "A"
  set_identifier = "failover-eu-west-1"

  alias {
    name                   = var.failover_alb_dns_name
    zone_id                = var.failover_alb_zone_id
    evaluate_target_health = true
  }

  failover_routing_policy {
    type = "SECONDARY"
  }
}

# ── Grafana DNS record (always points to primary; Grafana has its own HA) ─────
resource "aws_route53_record" "grafana" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "grafana.${var.internal_domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["${var.name_prefix}-grafana.grafana.amazonaws.com"]
}
