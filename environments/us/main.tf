# ─────────────────────────────────────────────────────────────────────────────
# Environment: us
# Region:      us-west-2
#
# Simplified version — no workspace logic. Tunables come from terraform.tfvars.
# State: us/terraform.tfstate
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "protex-tfstate-us"
    key            = "us/terraform.tfstate"
    region         = "us-west-2"
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
    DataRegion  = "US"
  }
}

provider "aws" {
  region = "us-west-2"
  assume_role { role_arn = "arn:aws:iam::${var.us_account_id}:role/TerraformDeployRole" }
  default_tags { tags = local.common_tags }
}

module "us_vpc" {
  source = "../../modules/networking"

  vpc_name             = "${local.name_prefix}-us"
  vpc_cidr             = "10.1.0.0/16"
  azs                  = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnet_cidrs  = ["10.1.0.0/24", "10.1.1.0/24", "10.1.2.0/24"]
  private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]
  data_subnet_cidrs    = ["10.1.20.0/24", "10.1.21.0/24", "10.1.22.0/24"]

  enable_nat_gateway      = true
  single_nat_gateway      = var.single_nat_gateway
  enable_flow_logs        = true
  flow_log_retention_days = var.flow_log_retention_days

  tags = local.common_tags
}

module "us_sg" {
  source = "../../modules/security_groups"

  vpc_id            = module.us_vpc.vpc_id
  environment       = "${local.name_prefix}-us"
  central_vpc_cidr  = var.central_vpc_cidr
  failover_vpc_cidr = var.failover_vpc_cidr
  db_port           = 5432
  tags              = local.common_tags
}

# ── Regional Monitoring — Connectivity Probe + Aurora Alarms ─────────────────

module "regional_monitoring" {
  source = "../../modules/regional_monitoring"

  name_prefix               = "${local.name_prefix}-us"
  region                    = "us"
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
