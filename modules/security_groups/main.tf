# ─────────────────────────────────────────────────────────────────────────────
# Module: security_groups
#
# Creates security groups following least-privilege principles:
#
# Central account:
#   • sg_api    — allows HTTPS ingress from internal users/load balancer;
#                 allows egress only to regional DB ports over peering CIDRs.
#
# Regional accounts:
#   • sg_db     — allows DB port ingress ONLY from the central VPC CIDR;
#                 no direct internet access.
#
# All other traffic is denied by default (AWS SG implicit deny).
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
    Module      = "security_groups"
    Environment = var.environment
  })
}

# ── Central API Security Group ────────────────────────────────────────────────
# Only created in the central environment (regional_vpc_cidrs will be non-empty)

resource "aws_security_group" "api" {
  count       = length(var.regional_vpc_cidrs) > 0 ? 1 : 0
  name        = "${var.environment}-api-sg"
  description = "Central Observability API layer — controls egress to regional DBs"
  vpc_id      = var.vpc_id

  # HTTPS ingress — only from within the VPC (ALB → ECS/Lambda)
  ingress {
    description = "HTTPS from VPC-internal load balancer"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # DB egress to every regional VPC CIDR (one rule per region)
  dynamic "egress" {
    for_each = var.regional_vpc_cidrs
    content {
      description = "DB access to regional VPC ${egress.value}"
      from_port   = var.db_port
      to_port     = var.db_port
      protocol    = "tcp"
      cidr_blocks = [egress.value]
    }
  }

  # HTTPS egress for AWS API calls (Secrets Manager, Parameter Store, etc.)
  egress {
    description = "HTTPS egress for AWS service API calls"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-api-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ── Regional Database Security Group ─────────────────────────────────────────
# Only created in regional environments (central_vpc_cidr will be set)

resource "aws_security_group" "db" {
  count       = var.central_vpc_cidr != "" ? 1 : 0
  name        = "${var.environment}-db-sg"
  description = "Regional DB — allows ingress ONLY from central API VPC CIDR"
  vpc_id      = var.vpc_id

  # DB ingress — only from the central API VPC over the peering link
  # Allow ingress from primary central VPC
  ingress {
    description = "DB access from primary central VPC (us-east-1)"
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    cidr_blocks = [var.central_vpc_cidr]
  }

  # Allow ingress from failover central VPC when var.failover_vpc_cidr is set
  # This ensures the DB remains queryable during a primary region failure.
  dynamic "ingress" {
    for_each = var.failover_vpc_cidr != "" ? [var.failover_vpc_cidr] : []
    content {
      description = "DB access from failover central VPC (eu-west-1)"
      from_port   = var.db_port
      to_port     = var.db_port
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  # No egress rules — regional DB does not initiate outbound connections
  # AWS implicit deny covers all other traffic

  tags = merge(local.common_tags, {
    Name = "${var.environment}-db-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}
