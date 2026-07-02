# ─────────────────────────────────────────────────────────────────────────────
# Environment: central
# Region:      eu-west-1  (primary)
# Account:     protex-central (111111111112)
#
# Simplified version of protex-observability — no dev/stg/prod workspaces.
# All tunables are plain variables; set them in terraform.tfvars.
#
# State: central/terraform.tfstate
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "protex-tfstate-central"
    key            = "central/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "protex-tfstate-lock"
  }
}

locals {
  name_prefix = "protex"

  common_tags = {
    Project     = "protex-observability"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}

# ── Providers ─────────────────────────────────────────────────────────────────

provider "aws" {
  region = "eu-west-1"
  assume_role { role_arn = "arn:aws:iam::${var.central_account_id}:role/TerraformDeployRole" }
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "eu"
  region = "eu-west-1"
  assume_role { role_arn = "arn:aws:iam::${var.eu_account_id}:role/TerraformPeeringAccepterRole" }
}
provider "aws" {
  alias  = "us"
  region = "us-west-2"
  assume_role { role_arn = "arn:aws:iam::${var.us_account_id}:role/TerraformPeeringAccepterRole" }
}
provider "aws" {
  alias  = "ca"
  region = "ca-central-1"
  assume_role { role_arn = "arn:aws:iam::${var.ca_account_id}:role/TerraformPeeringAccepterRole" }
}
provider "aws" {
  alias  = "apac"
  region = "ap-southeast-1"
  assume_role { role_arn = "arn:aws:iam::${var.apac_account_id}:role/TerraformPeeringAccepterRole" }
}

# ── Central VPC ───────────────────────────────────────────────────────────────

module "central_vpc" {
  source = "../../modules/networking"

  vpc_name             = "${local.name_prefix}-central"
  vpc_cidr             = var.central_vpc_cidr
  azs                  = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  data_subnet_cidrs    = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]

  enable_nat_gateway      = true
  single_nat_gateway      = var.single_nat_gateway
  enable_flow_logs        = true
  flow_log_retention_days = var.flow_log_retention_days

  tags = local.common_tags
}

# ── Security Groups ───────────────────────────────────────────────────────────

module "central_sg" {
  source = "../../modules/security_groups"

  vpc_id      = module.central_vpc.vpc_id
  environment = "${local.name_prefix}-central"
  db_port     = 5432

  regional_vpc_cidrs = [var.eu_vpc_cidr, var.us_vpc_cidr, var.ca_vpc_cidr, var.apac_vpc_cidr]
  tags               = local.common_tags
}

# ── SNS Alarm Topic ───────────────────────────────────────────────────────────

resource "aws_sns_topic" "alarms" {
  name              = "${local.name_prefix}-network-alarms"
  kms_master_key_id = "alias/aws/sns"
  tags              = local.common_tags
}

# ── VPC Peering ───────────────────────────────────────────────────────────────

module "peering_eu" {
  source    = "../../modules/vpc_peering"
  providers = { aws = aws, aws.accepter = aws.eu }

  peering_name              = "${local.name_prefix}-central-to-eu"
  requester_vpc_id          = module.central_vpc.vpc_id
  requester_vpc_cidr        = var.central_vpc_cidr
  requester_region          = var.aws_region
  requester_account_id      = var.central_account_id
  requester_route_table_ids = module.central_vpc.private_route_table_ids
  accepter_vpc_id           = var.eu_vpc_id
  accepter_vpc_cidr         = var.eu_vpc_cidr
  accepter_region           = "eu-west-1"
  accepter_account_id       = var.eu_account_id
  accepter_route_table_ids  = var.eu_private_route_table_ids
  tags                      = local.common_tags
}

module "peering_us" {
  source    = "../../modules/vpc_peering"
  providers = { aws = aws, aws.accepter = aws.us }

  peering_name              = "${local.name_prefix}-central-to-us"
  requester_vpc_id          = module.central_vpc.vpc_id
  requester_vpc_cidr        = var.central_vpc_cidr
  requester_region          = var.aws_region
  requester_account_id      = var.central_account_id
  requester_route_table_ids = module.central_vpc.private_route_table_ids
  accepter_vpc_id           = var.us_vpc_id
  accepter_vpc_cidr         = var.us_vpc_cidr
  accepter_region           = "us-west-2"
  accepter_account_id       = var.us_account_id
  accepter_route_table_ids  = var.us_private_route_table_ids
  tags                      = local.common_tags
}

module "peering_ca" {
  source    = "../../modules/vpc_peering"
  providers = { aws = aws, aws.accepter = aws.ca }

  peering_name              = "${local.name_prefix}-central-to-ca"
  requester_vpc_id          = module.central_vpc.vpc_id
  requester_vpc_cidr        = var.central_vpc_cidr
  requester_region          = var.aws_region
  requester_account_id      = var.central_account_id
  requester_route_table_ids = module.central_vpc.private_route_table_ids
  accepter_vpc_id           = var.ca_vpc_id
  accepter_vpc_cidr         = var.ca_vpc_cidr
  accepter_region           = "ca-central-1"
  accepter_account_id       = var.ca_account_id
  accepter_route_table_ids  = var.ca_private_route_table_ids
  tags                      = local.common_tags
}

module "peering_apac" {
  source    = "../../modules/vpc_peering"
  providers = { aws = aws, aws.accepter = aws.apac }

  peering_name              = "${local.name_prefix}-central-to-apac"
  requester_vpc_id          = module.central_vpc.vpc_id
  requester_vpc_cidr        = var.central_vpc_cidr
  requester_region          = var.aws_region
  requester_account_id      = var.central_account_id
  requester_route_table_ids = module.central_vpc.private_route_table_ids
  accepter_vpc_id           = var.apac_vpc_id
  accepter_vpc_cidr         = var.apac_vpc_cidr
  accepter_region           = "ap-southeast-1"
  accepter_account_id       = var.apac_account_id
  accepter_route_table_ids  = var.apac_private_route_table_ids
  tags                      = local.common_tags
}

# ── Monitoring ────────────────────────────────────────────────────────────────

module "monitoring" {
  source = "../../modules/monitoring"

  environment              = "${local.name_prefix}-central"
  vpc_id                   = module.central_vpc.vpc_id
  alarm_sns_topic_arn      = aws_sns_topic.alarms.arn
  latency_threshold_ms     = var.latency_threshold_ms
  error_rate_threshold_pct = var.error_rate_threshold_pct

  peering_connection_ids = {
    eu   = module.peering_eu.peering_connection_id
    us   = module.peering_us.peering_connection_id
    ca   = module.peering_ca.peering_connection_id
    apac = module.peering_apac.peering_connection_id
  }

  tags = local.common_tags
}

# ── Prometheus + Grafana ──────────────────────────────────────────────────────
# Amazon Managed Prometheus receives remote_write from the Video Recorder Server
# (edge layer). Amazon Managed Grafana queries AMP + CloudWatch for unified
# dashboards AND connects directly to regional Aurora clusters over VPC Peering
# as PostgreSQL data sources. Auth via AWS SSO — no separate user database.

module "observability" {
  source = "../../modules/observability"

  name_prefix         = local.name_prefix
  alert_sns_topic_arn = aws_sns_topic.alarms.arn

  amp_log_retention_days = var.flow_log_retention_days

  # VPC configuration so AMG can reach private Aurora endpoints via VPC Peering
  grafana_subnet_ids         = module.central_vpc.private_subnet_ids
  grafana_security_group_ids = [module.central_sg.sg_api_id]

  # Regional Aurora endpoints for Grafana PostgreSQL data sources
  eu_aurora_endpoint   = var.eu_aurora_endpoint
  eu_aurora_password   = var.eu_aurora_password
  us_aurora_endpoint   = var.us_aurora_endpoint
  us_aurora_password   = var.us_aurora_password
  ca_aurora_endpoint   = var.ca_aurora_endpoint
  ca_aurora_password   = var.ca_aurora_password
  apac_aurora_endpoint = var.apac_aurora_endpoint
  apac_aurora_password = var.apac_aurora_password

  tags = local.common_tags
}

# ── Route 53 Active-Passive Failover ─────────────────────────────────────────
# Wires up DNS failover between this primary environment (eu-west-1) and the
# DR environment (us-east-1, environments/central-dr/).
#
# The failover_alb_dns_name and failover_vpc_id are outputs from the
# central-dr environment apply — populate them in terraform.tfvars after
# environments/central-dr/ has been deployed.
#
# Failover timeline:
#   health_check (10s × 3 failures) + DNS TTL (30s) = ~60s worst case

module "route53_failover" {
  source = "../../modules/route53_failover"

  name_prefix          = local.name_prefix
  internal_domain_name = var.internal_domain_name

  # Primary side (this environment)
  primary_alb_dns_name = var.primary_alb_dns_name
  primary_alb_zone_id  = var.primary_alb_zone_id
  primary_vpc_id       = module.central_vpc.vpc_id

  # Failover side (environments/central-dr outputs)
  failover_alb_dns_name = var.failover_alb_dns_name
  failover_alb_zone_id  = var.failover_alb_zone_id
  failover_vpc_id       = var.failover_vpc_id
  failover_region       = "us-east-1"

  health_check_interval          = 10
  health_check_failure_threshold = 3

  tags = local.common_tags
}

# ── Edge Device Fleet Monitoring ──────────────────────────────────────────────
# AMP recording rules and alerts for Linux-based Protex edge devices.
# Node Exporter + Protex app exporter run on each device.
# Video Recorder Server scrapes all devices and remote_writes to AMP.
# See modules/edge_monitoring/config/ for Prometheus and heartbeat configs.

module "edge_monitoring" {
  source = "../../modules/edge_monitoring"

  name_prefix      = "protex"
  amp_workspace_id = module.observability[0].amp_workspace_id
  alarm_sns_topic_arn = aws_sns_topic.alarms[0].arn

  device_offline_threshold_minutes = 5
  cpu_threshold_pct                = 90
  disk_free_threshold_gb           = 10
  inference_error_threshold        = 5

  tags = local.common_tags
}
