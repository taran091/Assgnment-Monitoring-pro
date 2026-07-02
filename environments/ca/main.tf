# ─────────────────────────────────────────────────────────────────────────────
# Environment: ca
# Region:      ca-central-1
#
# Simplified version — no workspace logic. Tunables come from terraform.tfvars.
# State: ca/terraform.tfstate
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "protex-tfstate-ca"
    key            = "ca/terraform.tfstate"
    region         = "ca-central-1"
    encrypt        = true
    dynamodb_table = "protex-tfstate-lock"
  }
}

locals {
  name_prefix = "protex-${var.region_label}"

  common_tags = {
    Project     = "protex-observability"
    Environment = "prod"
    ManagedBy   = "terraform"
    DataRegion  = "CA"
  }
}

provider "aws" {
  region = "ca-central-1"
  assume_role { role_arn = "arn:aws:iam::${var.ca_account_id}:role/TerraformDeployRole" }
  default_tags { tags = local.common_tags }
}

module "ca_vpc" {
  source = "../../modules/networking"

  vpc_name             = "${local.name_prefix}-ca"
  vpc_cidr             = "10.3.0.0/16"
  azs                  = ["ca-central-1a", "ca-central-1b", "ca-central-1d"]
  public_subnet_cidrs  = ["10.3.0.0/24", "10.3.1.0/24", "10.3.2.0/24"]
  private_subnet_cidrs = ["10.3.10.0/24", "10.3.11.0/24", "10.3.12.0/24"]
  data_subnet_cidrs    = ["10.3.20.0/24", "10.3.21.0/24", "10.3.22.0/24"]

  enable_nat_gateway      = true
  single_nat_gateway      = var.single_nat_gateway
  enable_flow_logs        = true
  flow_log_retention_days = var.flow_log_retention_days

  tags = local.common_tags
}

module "ca_sg" {
  source = "../../modules/security_groups"

  vpc_id            = module.ca_vpc.vpc_id
  environment       = "${local.name_prefix}-ca"
  central_vpc_cidr  = var.central_vpc_cidr
  failover_vpc_cidr = var.failover_vpc_cidr
  db_port           = 5432
  tags              = local.common_tags
}

# ── Regional Monitoring — Connectivity Probe + Aurora Alarms ─────────────────

module "regional_monitoring" {
  source = "../../modules/regional_monitoring"

  name_prefix               = "${local.name_prefix}-ca"
  region                    = "ca"
  alarm_sns_topic_arn       = var.central_alarm_sns_topic_arn
  aurora_cluster_identifier = var.aurora_cluster_identifier
  aurora_db_endpoint        = var.aurora_db_endpoint
  aurora_db_port            = 5432

  max_connections_threshold     = 800
  select_latency_threshold_ms   = 200
  replica_lag_threshold_seconds = 30
  probe_schedule                = "rate(1 minute)"

  tags = local.common_tags
}
