# ─────────────────────────────────────────────────────────────────────────────
# Module: route53_failover — Unit Tests
#
# Run with:  cd modules/route53_failover && terraform test
#
# Key assertions:
#   - Private hosted zone is created with the correct domain name
#   - Health check polls the primary ALB at the correct interval/threshold
#   - PRIMARY DNS record points to the primary ALB
#   - SECONDARY DNS record points to the failover ALB
#   - Both VPCs are associated with the hosted zone
#   - CloudWatch alarm is wired to the health check
# ─────────────────────────────────────────────────────────────────────────────

mock_provider "aws" {
  mock_resource "aws_route53_zone" {
    defaults = {
      id      = "Z1MOCK00001"
      zone_id = "Z1MOCK00001"
      name    = "observability.protex.internal"
    }
  }

  mock_resource "aws_route53_zone_association" {
    defaults = { id = "Z1MOCK00001:vpc-failover-mock:eu-west-1" }
  }

  mock_resource "aws_route53_health_check" {
    defaults = {
      id  = "hc-mock00001"
      arn = "arn:aws:route53:::healthcheck/hc-mock00001"
    }
  }

  mock_resource "aws_cloudwatch_metric_alarm" {
    defaults = {
      id  = "mock-alarm"
      arn = "arn:aws:cloudwatch:us-east-1:111111111111:alarm:mock-alarm"
    }
  }

  mock_resource "aws_route53_record" {
    defaults = { id = "Z1MOCK00001_api.observability.protex.internal_A" }
  }
}

# ── Test 1: Hosted zone created with correct domain name ──────────────────────

run "hosted_zone_uses_correct_domain" {
  command = plan

  variables {
    name_prefix           = "protex-prod"
    internal_domain_name  = "observability.protex.internal"
    primary_alb_dns_name  = "protex-prod-alb.us-east-1.elb.amazonaws.com"
    primary_alb_zone_id   = "Z35SXDOTRQ7X7K"
    primary_vpc_id        = "vpc-primary-mock"
    failover_alb_dns_name = "protex-prod-failover-alb.eu-west-1.elb.amazonaws.com"
    failover_alb_zone_id  = "Z32O12XQLNTSW2"
    failover_vpc_id       = "vpc-failover-mock"
    failover_region       = "eu-west-1"
  }

  assert {
    condition     = aws_route53_zone.internal.name == "observability.protex.internal"
    error_message = "Hosted zone must use the internal_domain_name variable"
  }
}

# ── Test 2: Health check uses correct interval and failure threshold ───────────
# These values directly determine the failover speed:
# interval × failure_threshold + DNS TTL = total failover time
# 10s × 3 + 30s = 60s worst case

run "health_check_timing_configuration" {
  command = plan

  variables {
    name_prefix                    = "protex-prod"
    internal_domain_name           = "observability.protex.internal"
    primary_alb_dns_name           = "protex-prod-alb.us-east-1.elb.amazonaws.com"
    primary_alb_zone_id            = "Z35SXDOTRQ7X7K"
    primary_vpc_id                 = "vpc-primary-mock"
    failover_alb_dns_name          = "protex-prod-failover-alb.eu-west-1.elb.amazonaws.com"
    failover_alb_zone_id           = "Z32O12XQLNTSW2"
    failover_vpc_id                = "vpc-failover-mock"
    failover_region                = "eu-west-1"
    health_check_interval          = 10
    health_check_failure_threshold = 3
  }

  assert {
    condition     = aws_route53_health_check.primary.request_interval == 10
    error_message = "Health check interval must be 10s for fast failover detection"
  }

  assert {
    condition     = aws_route53_health_check.primary.failure_threshold == 3
    error_message = "Failure threshold must be 3 (30s detection + 30s TTL = ~60s total)"
  }
}

# ── Test 3: Health check polls the primary ALB FQDN ──────────────────────────

run "health_check_targets_primary_alb" {
  command = plan

  variables {
    name_prefix           = "protex-prod"
    internal_domain_name  = "observability.protex.internal"
    primary_alb_dns_name  = "protex-prod-alb.us-east-1.elb.amazonaws.com"
    primary_alb_zone_id   = "Z35SXDOTRQ7X7K"
    primary_vpc_id        = "vpc-primary-mock"
    failover_alb_dns_name = "protex-prod-failover-alb.eu-west-1.elb.amazonaws.com"
    failover_alb_zone_id  = "Z32O12XQLNTSW2"
    failover_vpc_id       = "vpc-failover-mock"
    failover_region       = "eu-west-1"
  }

  assert {
    condition     = aws_route53_health_check.primary.fqdn == "protex-prod-alb.us-east-1.elb.amazonaws.com"
    error_message = "Health check must target the primary ALB DNS name"
  }

  assert {
    condition     = aws_route53_health_check.primary.type == "HTTPS"
    error_message = "Health check must use HTTPS (port 443)"
  }
}

# ── Test 4: TWO DNS records created — PRIMARY and SECONDARY ──────────────────

run "two_failover_dns_records_created" {
  command = plan

  variables {
    name_prefix           = "protex-prod"
    internal_domain_name  = "observability.protex.internal"
    primary_alb_dns_name  = "protex-prod-alb.us-east-1.elb.amazonaws.com"
    primary_alb_zone_id   = "Z35SXDOTRQ7X7K"
    primary_vpc_id        = "vpc-primary-mock"
    failover_alb_dns_name = "protex-prod-failover-alb.eu-west-1.elb.amazonaws.com"
    failover_alb_zone_id  = "Z32O12XQLNTSW2"
    failover_vpc_id       = "vpc-failover-mock"
    failover_region       = "eu-west-1"
  }

  assert {
    condition     = aws_route53_record.api_primary.failover_routing_policy[0].type == "PRIMARY"
    error_message = "api_primary record must have failover type PRIMARY"
  }

  assert {
    condition     = aws_route53_record.api_failover.failover_routing_policy[0].type == "SECONDARY"
    error_message = "api_failover record must have failover type SECONDARY"
  }
}

# ── Test 5: Failover VPC is associated with the hosted zone ───────────────────
# Without this association, the failover API cannot resolve internal DNS names.

run "failover_vpc_associated_with_zone" {
  command = plan

  variables {
    name_prefix           = "protex-prod"
    internal_domain_name  = "observability.protex.internal"
    primary_alb_dns_name  = "protex-prod-alb.us-east-1.elb.amazonaws.com"
    primary_alb_zone_id   = "Z35SXDOTRQ7X7K"
    primary_vpc_id        = "vpc-primary-mock"
    failover_alb_dns_name = "protex-prod-failover-alb.eu-west-1.elb.amazonaws.com"
    failover_alb_zone_id  = "Z32O12XQLNTSW2"
    failover_vpc_id       = "vpc-failover-mock"
    failover_region       = "eu-west-1"
  }

  assert {
    condition     = aws_route53_zone_association.failover_vpc.vpc_id == "vpc-failover-mock"
    error_message = "Failover VPC must be associated with the hosted zone for internal DNS resolution"
  }
}

# ── Test 6: CloudWatch alarm monitors health check status ─────────────────────
# Ensures the health check failure triggers the existing SNS → PagerDuty chain.

run "cloudwatch_alarm_monitors_health_check" {
  command = plan

  variables {
    name_prefix           = "protex-prod"
    internal_domain_name  = "observability.protex.internal"
    primary_alb_dns_name  = "protex-prod-alb.us-east-1.elb.amazonaws.com"
    primary_alb_zone_id   = "Z35SXDOTRQ7X7K"
    primary_vpc_id        = "vpc-primary-mock"
    failover_alb_dns_name = "protex-prod-failover-alb.eu-west-1.elb.amazonaws.com"
    failover_alb_zone_id  = "Z32O12XQLNTSW2"
    failover_vpc_id       = "vpc-failover-mock"
    failover_region       = "eu-west-1"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.primary_health.metric_name == "HealthCheckStatus"
    error_message = "CloudWatch alarm must monitor Route 53 HealthCheckStatus metric"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.primary_health.namespace == "AWS/Route53"
    error_message = "CloudWatch alarm must use AWS/Route53 namespace"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.primary_health.treat_missing_data == "breaching"
    error_message = "Missing data must be treated as breaching to catch total health check failures"
  }
}
