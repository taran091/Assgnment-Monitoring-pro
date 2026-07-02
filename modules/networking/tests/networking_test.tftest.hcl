# ─────────────────────────────────────────────────────────────────────────────
# Module: networking — Unit Tests
#
# Run with:  cd modules/networking && terraform test
#
# All tests use mock_provider so NO AWS credentials or network access needed.
# mock_provider intercepts every AWS API call and returns the mocked values,
# allowing a full plan-time assertion without touching a real account.
# ─────────────────────────────────────────────────────────────────────────────

mock_provider "aws" {
  mock_resource "aws_vpc" {
    defaults = {
      id                     = "vpc-mock00001"
      arn                    = "arn:aws:ec2:us-east-1:111111111111:vpc/vpc-mock00001"
      default_route_table_id = "rtb-mock00000"
    }
  }

  mock_resource "aws_internet_gateway" {
    defaults = { id = "igw-mock00001" }
  }

  mock_resource "aws_subnet" {
    defaults = { id = "subnet-mock00001" }
  }

  mock_resource "aws_eip" {
    defaults = { id = "eipalloc-mock001", allocation_id = "eipalloc-mock001" }
  }

  mock_resource "aws_nat_gateway" {
    defaults = { id = "nat-mock00001" }
  }

  mock_resource "aws_route_table" {
    defaults = { id = "rtb-mock00001" }
  }

  mock_resource "aws_route" {
    defaults = { id = "r-mock00001" }
  }

  mock_resource "aws_route_table_association" {
    defaults = { id = "rtbassoc-mock001" }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = { id = "/aws/vpc/flow-logs/test", arn = "arn:aws:logs:us-east-1:111111111111:log-group:/aws/vpc/flow-logs/test" }
  }

  mock_resource "aws_iam_role" {
    defaults = { id = "test-flow-logs-role", arn = "arn:aws:iam::111111111111:role/test-flow-logs-role" }
  }

  mock_resource "aws_iam_role_policy" {
    defaults = { id = "test-flow-logs-role:test-flow-logs-policy" }
  }

  mock_resource "aws_flow_log" {
    defaults = { id = "fl-mock00001" }
  }
}

# ── Test 1: Three AZs produce nine subnets (3 public + 3 private + 3 data) ───

run "three_azs_create_nine_subnets" {
  command = plan

  variables {
    vpc_name                = "protex-prod-central"
    vpc_cidr                = "10.0.0.0/16"
    azs                     = ["us-east-1a", "us-east-1b", "us-east-1c"]
    public_subnet_cidrs     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
    private_subnet_cidrs    = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
    data_subnet_cidrs       = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
    enable_nat_gateway      = true
    single_nat_gateway      = false
    enable_flow_logs        = false
    flow_log_retention_days = 90
  }

  assert {
    condition     = length(aws_subnet.public) == 3
    error_message = "Expected 3 public subnets for 3 AZs, got ${length(aws_subnet.public)}"
  }

  assert {
    condition     = length(aws_subnet.private) == 3
    error_message = "Expected 3 private subnets for 3 AZs, got ${length(aws_subnet.private)}"
  }

  assert {
    condition     = length(aws_subnet.data) == 3
    error_message = "Expected 3 data subnets for 3 AZs, got ${length(aws_subnet.data)}"
  }
}

# ── Test 2: VPC CIDR and Name tag are set correctly ──────────────────────────

run "vpc_cidr_and_name_tag" {
  command = plan

  variables {
    vpc_name                = "protex-prod-central"
    vpc_cidr                = "10.0.0.0/16"
    azs                     = ["us-east-1a", "us-east-1b"]
    public_subnet_cidrs     = ["10.0.0.0/24", "10.0.1.0/24"]
    private_subnet_cidrs    = ["10.0.10.0/24", "10.0.11.0/24"]
    data_subnet_cidrs       = ["10.0.20.0/24", "10.0.21.0/24"]
    enable_nat_gateway      = false
    single_nat_gateway      = false
    enable_flow_logs        = false
    flow_log_retention_days = 90
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR must match input variable"
  }

  assert {
    condition     = aws_vpc.this.tags["Name"] == "protex-prod-central"
    error_message = "VPC Name tag must equal vpc_name variable"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames == true
    error_message = "DNS hostnames must be enabled for Aurora endpoint resolution across peering"
  }
}

# ── Test 3: dev workspace — single_nat_gateway creates exactly 1 NAT GW ──────

run "dev_single_nat_gateway" {
  command = plan

  variables {
    vpc_name                = "protex-dev-central"
    vpc_cidr                = "10.0.0.0/16"
    azs                     = ["us-east-1a", "us-east-1b", "us-east-1c"]
    public_subnet_cidrs     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
    private_subnet_cidrs    = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
    data_subnet_cidrs       = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
    enable_nat_gateway      = true
    single_nat_gateway      = true # dev cost-saving mode
    enable_flow_logs        = false
    flow_log_retention_days = 14
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "single_nat_gateway=true must create exactly 1 NAT Gateway (dev cost saving)"
  }

  assert {
    condition     = length(aws_eip.nat) == 1
    error_message = "single_nat_gateway=true must allocate exactly 1 EIP"
  }
}

# ── Test 4: prod workspace — one NAT GW per AZ for full HA ───────────────────

run "prod_nat_gateway_per_az" {
  command = plan

  variables {
    vpc_name                = "protex-prod-central"
    vpc_cidr                = "10.0.0.0/16"
    azs                     = ["us-east-1a", "us-east-1b", "us-east-1c"]
    public_subnet_cidrs     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
    private_subnet_cidrs    = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
    data_subnet_cidrs       = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
    enable_nat_gateway      = true
    single_nat_gateway      = false # prod — one per AZ
    enable_flow_logs        = false
    flow_log_retention_days = 90
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "single_nat_gateway=false with 3 AZs must create 3 NAT Gateways"
  }
}

# ── Test 5: Flow logs created with correct retention when enabled ─────────────

run "flow_logs_enabled" {
  command = plan

  variables {
    vpc_name                = "protex-prod-eu"
    vpc_cidr                = "10.2.0.0/16"
    azs                     = ["eu-west-1a", "eu-west-1b"]
    public_subnet_cidrs     = ["10.2.0.0/24", "10.2.1.0/24"]
    private_subnet_cidrs    = ["10.2.10.0/24", "10.2.11.0/24"]
    data_subnet_cidrs       = ["10.2.20.0/24", "10.2.21.0/24"]
    enable_nat_gateway      = false
    single_nat_gateway      = false
    enable_flow_logs        = true
    flow_log_retention_days = 365 # EU GDPR: 365 days
  }

  assert {
    condition     = length(aws_flow_log.this) == 1
    error_message = "Flow log resource must be created when enable_flow_logs=true"
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs[0].retention_in_days == 365
    error_message = "EU flow log retention must be 365 days for GDPR compliance"
  }
}

# ── Test 6: Subnet tier tags distinguish public/private/data ─────────────────

run "subnet_tier_tags" {
  command = plan

  variables {
    vpc_name                = "protex-prod-central"
    vpc_cidr                = "10.0.0.0/16"
    azs                     = ["us-east-1a"]
    public_subnet_cidrs     = ["10.0.0.0/24"]
    private_subnet_cidrs    = ["10.0.10.0/24"]
    data_subnet_cidrs       = ["10.0.20.0/24"]
    enable_nat_gateway      = false
    single_nat_gateway      = false
    enable_flow_logs        = false
    flow_log_retention_days = 90
  }

  assert {
    condition     = aws_subnet.public[0].tags["Tier"] == "public"
    error_message = "Public subnets must have Tier=public tag"
  }

  assert {
    condition     = aws_subnet.private[0].tags["Tier"] == "private"
    error_message = "Private subnets must have Tier=private tag"
  }

  assert {
    condition     = aws_subnet.data[0].tags["Tier"] == "data"
    error_message = "Data subnets must have Tier=data tag"
  }
}
