# ─────────────────────────────────────────────────────────────────────────────
# Environment: eu
# Region:      eu-west-1
#
# Simplified version — no workspace logic. Tunables come from terraform.tfvars.
# State: eu/terraform.tfstate
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "protex-tfstate-eu"
    key            = "eu/terraform.tfstate"
    region         = "eu-west-1"
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
    DataRegion  = "EU"
  }
}

provider "aws" {
  region = "eu-west-1"
  assume_role { role_arn = "arn:aws:iam::${var.eu_account_id}:role/TerraformDeployRole" }
  default_tags { tags = local.common_tags }
}

module "eu_vpc" {
  source = "../../modules/networking"

  vpc_name             = "${local.name_prefix}-eu"
  vpc_cidr             = "10.2.0.0/16"
  azs                  = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  public_subnet_cidrs  = ["10.2.0.0/24", "10.2.1.0/24", "10.2.2.0/24"]
  private_subnet_cidrs = ["10.2.10.0/24", "10.2.11.0/24", "10.2.12.0/24"]
  data_subnet_cidrs    = ["10.2.20.0/24", "10.2.21.0/24", "10.2.22.0/24"]

  enable_nat_gateway      = true
  single_nat_gateway      = var.single_nat_gateway
  enable_flow_logs        = true
  flow_log_retention_days = var.flow_log_retention_days

  tags = local.common_tags
}

module "eu_sg" {
  source = "../../modules/security_groups"

  vpc_id            = module.eu_vpc.vpc_id
  environment       = "${local.name_prefix}-eu"
  central_vpc_cidr  = var.central_vpc_cidr
  failover_vpc_cidr = var.failover_vpc_cidr
  db_port           = 5432
  tags              = local.common_tags
}

# ── Regional Monitoring — Connectivity Probe + Aurora Alarms ─────────────────

module "regional_monitoring" {
  source = "../../modules/regional_monitoring"

  name_prefix               = "${local.name_prefix}-eu"
  region                    = "eu"
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
