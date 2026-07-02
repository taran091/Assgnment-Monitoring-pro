# ─────────────────────────────────────────────────────────────────────────────
# Environment: central-dr
# Region:      us-east-1  (disaster recovery / warm standby)
# Account:     protex-central (same account as primary, different region)
# CIDR:        10.5.0.0/16  (non-overlapping with all other VPCs)
#
# Simplified version — no workspace logic. Tunables come from terraform.tfvars.
#
# This is the warm-standby deployment of the central Observability API.
# It sits idle under normal operation. Route 53 automatically directs traffic
# here when the primary (eu-west-1) health check fails.
#
# Both this VPC and the primary central VPC are peered to all 4 regional
# accounts. When failover activates, this API can immediately query all
# regional databases without manual intervention.
#
# Deployment order:
#   1. Deploy environments/central/ first.
#   2. Deploy this environment.
#   3. Record outputs (failover_vpc_id, etc.) and pass to central's
#      terraform.tfvars to complete the Route 53 DNS wiring.
#
# State: central-dr/terraform.tfstate
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "protex-tfstate-central"
    key            = "central-dr/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "protex-tfstate-lock"
  }
}

locals {
  name_prefix = "protex-dr"

  common_tags = {
    Project     = "protex-observability"
    Environment = "prod"
    Role        = "central-dr"
    ManagedBy   = "terraform"
  }
}

# ── Providers ─────────────────────────────────────────────────────────────────

provider "aws" {
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::${var.central_account_id}:role/TerraformDeployRole"
  }
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "eu"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::${var.eu_account_id}:role/TerraformPeeringAccepterRole"
  }
}
provider "aws" {
  alias  = "us"
  region = "us-west-2"
  assume_role {
    role_arn = "arn:aws:iam::${var.us_account_id}:role/TerraformPeeringAccepterRole"
  }
}
provider "aws" {
  alias  = "ca"
  region = "ca-central-1"
  assume_role {
    role_arn = "arn:aws:iam::${var.ca_account_id}:role/TerraformPeeringAccepterRole"
  }
}
provider "aws" {
  alias  = "apac"
  region = "ap-southeast-1"
  assume_role {
    role_arn = "arn:aws:iam::${var.apac_account_id}:role/TerraformPeeringAccepterRole"
  }
}

# ── DR Central VPC (us-east-1, 10.5.0.0/16) ──────────────────────────────────
# Separate CIDR from primary (10.0.0.0/16) so both can peer to regional VPCs
# simultaneously without CIDR conflicts.

module "dr_vpc" {
  source = "../../modules/networking"

  vpc_name             = "${local.name_prefix}-central"
  vpc_cidr             = "10.5.0.0/16"
  azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs  = ["10.5.0.0/24", "10.5.1.0/24", "10.5.2.0/24"]
  private_subnet_cidrs = ["10.5.10.0/24", "10.5.11.0/24", "10.5.12.0/24"]
  data_subnet_cidrs    = ["10.5.20.0/24", "10.5.21.0/24", "10.5.22.0/24"]

  enable_nat_gateway      = true
  single_nat_gateway      = var.single_nat_gateway
  enable_flow_logs        = true
  flow_log_retention_days = var.flow_log_retention_days

  tags = local.common_tags
}

# ── Security Groups ───────────────────────────────────────────────────────────

module "dr_sg" {
  source = "../../modules/security_groups"

  vpc_id      = module.dr_vpc.vpc_id
  environment = "${local.name_prefix}-central"
  db_port     = 5432

  regional_vpc_cidrs = [
    var.eu_vpc_cidr,
    var.us_vpc_cidr,
    var.ca_vpc_cidr,
    var.apac_vpc_cidr,
  ]

  tags = local.common_tags
}

# ── VPC Peering — DR Central ↔ All Regions ───────────────────────────────────
# Each regional account gets a second peering connection to the DR VPC.
# Regional DB security groups allow traffic from both 10.0.0.0/16 (primary)
# and 10.5.0.0/16 (DR) so either central can query the database.

module "dr_peering_eu" {
  source    = "../../modules/vpc_peering"
  providers = { aws = aws, aws.accepter = aws.eu }

  peering_name              = "${local.name_prefix}-central-to-eu"
  requester_vpc_id          = module.dr_vpc.vpc_id
  requester_vpc_cidr        = "10.5.0.0/16"
  requester_region          = "us-east-1"
  requester_account_id      = var.central_account_id
  requester_route_table_ids = module.dr_vpc.private_route_table_ids
  accepter_vpc_id           = var.eu_vpc_id
  accepter_vpc_cidr         = var.eu_vpc_cidr
  accepter_region           = "eu-west-1"
  accepter_account_id       = var.eu_account_id
  accepter_route_table_ids  = var.eu_private_route_table_ids
  tags                      = local.common_tags
}

module "dr_peering_us" {
  source    = "../../modules/vpc_peering"
  providers = { aws = aws, aws.accepter = aws.us }

  peering_name              = "${local.name_prefix}-central-to-us"
  requester_vpc_id          = module.dr_vpc.vpc_id
  requester_vpc_cidr        = "10.5.0.0/16"
  requester_region          = "us-east-1"
  requester_account_id      = var.central_account_id
  requester_route_table_ids = module.dr_vpc.private_route_table_ids
  accepter_vpc_id           = var.us_vpc_id
  accepter_vpc_cidr         = var.us_vpc_cidr
  accepter_region           = "us-west-2"
  accepter_account_id       = var.us_account_id
  accepter_route_table_ids  = var.us_private_route_table_ids
  tags                      = local.common_tags
}

module "dr_peering_ca" {
  source    = "../../modules/vpc_peering"
  providers = { aws = aws, aws.accepter = aws.ca }

  peering_name              = "${local.name_prefix}-central-to-ca"
  requester_vpc_id          = module.dr_vpc.vpc_id
  requester_vpc_cidr        = "10.5.0.0/16"
  requester_region          = "us-east-1"
  requester_account_id      = var.central_account_id
  requester_route_table_ids = module.dr_vpc.private_route_table_ids
  accepter_vpc_id           = var.ca_vpc_id
  accepter_vpc_cidr         = var.ca_vpc_cidr
  accepter_region           = "ca-central-1"
  accepter_account_id       = var.ca_account_id
  accepter_route_table_ids  = var.ca_private_route_table_ids
  tags                      = local.common_tags
}

module "dr_peering_apac" {
  source    = "../../modules/vpc_peering"
  providers = { aws = aws, aws.accepter = aws.apac }

  peering_name              = "${local.name_prefix}-central-to-apac"
  requester_vpc_id          = module.dr_vpc.vpc_id
  requester_vpc_cidr        = "10.5.0.0/16"
  requester_region          = "us-east-1"
  requester_account_id      = var.central_account_id
  requester_route_table_ids = module.dr_vpc.private_route_table_ids
  accepter_vpc_id           = var.apac_vpc_id
  accepter_vpc_cidr         = var.apac_vpc_cidr
  accepter_region           = "ap-southeast-1"
  accepter_account_id       = var.apac_account_id
  accepter_route_table_ids  = var.apac_private_route_table_ids
  tags                      = local.common_tags
}
