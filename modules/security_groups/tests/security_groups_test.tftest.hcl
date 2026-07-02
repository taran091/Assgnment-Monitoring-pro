# ─────────────────────────────────────────────────────────────────────────────
# Module: security_groups — Unit Tests
#
# Run with:  cd modules/security_groups && terraform test
#
# Key assertions:
#   - API SG is ONLY created in central (when regional_vpc_cidrs is non-empty)
#   - DB SG is ONLY created in regional accounts (when central_vpc_cidr is set)
#   - Never both — a VPC is either central or regional, not both
#   - Names carry the environment prefix for workspace isolation
# ─────────────────────────────────────────────────────────────────────────────

mock_provider "aws" {
  mock_resource "aws_security_group" {
    defaults = {
      id  = "sg-mock00001"
      arn = "arn:aws:ec2:us-east-1:111111111111:security-group/sg-mock00001"
    }
  }
}

# ── Test 1: Central account — API SG created, DB SG not created ──────────────

run "central_creates_api_sg_only" {
  command = plan

  variables {
    vpc_id             = "vpc-mock00001"
    environment        = "prod-central"
    db_port            = 5432
    regional_vpc_cidrs = ["10.1.0.0/16", "10.2.0.0/16", "10.3.0.0/16", "10.4.0.0/16"]
    central_vpc_cidr   = ""
  }

  assert {
    condition     = length(aws_security_group.api) == 1
    error_message = "API SG must be created in the central account when regional_vpc_cidrs is provided"
  }

  assert {
    condition     = length(aws_security_group.db) == 0
    error_message = "DB SG must NOT be created in the central account (central_vpc_cidr is empty)"
  }
}

# ── Test 2: Regional account — DB SG created, API SG not created ─────────────

run "regional_creates_db_sg_only" {
  command = plan

  variables {
    vpc_id             = "vpc-mock00002"
    environment        = "prod-eu"
    db_port            = 5432
    regional_vpc_cidrs = []
    central_vpc_cidr   = "10.0.0.0/16"
  }

  assert {
    condition     = length(aws_security_group.db) == 1
    error_message = "DB SG must be created in regional accounts when central_vpc_cidr is provided"
  }

  assert {
    condition     = length(aws_security_group.api) == 0
    error_message = "API SG must NOT be created in regional accounts (regional_vpc_cidrs is empty)"
  }
}

# ── Test 3: API SG name carries environment prefix ───────────────────────────

run "api_sg_name_includes_environment" {
  command = plan

  variables {
    vpc_id             = "vpc-mock00001"
    environment        = "prod-central"
    db_port            = 5432
    regional_vpc_cidrs = ["10.1.0.0/16"]
    central_vpc_cidr   = ""
  }

  assert {
    condition     = aws_security_group.api[0].name == "prod-central-api-sg"
    error_message = "API SG name must be '{environment}-api-sg' for workspace isolation in the AWS console"
  }
}

# ── Test 4: DB SG name carries environment prefix ────────────────────────────

run "db_sg_name_includes_environment" {
  command = plan

  variables {
    vpc_id             = "vpc-mock00002"
    environment        = "prod-eu"
    db_port            = 5432
    regional_vpc_cidrs = []
    central_vpc_cidr   = "10.0.0.0/16"
  }

  assert {
    condition     = aws_security_group.db[0].name == "prod-eu-db-sg"
    error_message = "DB SG name must be '{environment}-db-sg'"
  }
}

# ── Test 5: Custom DB port is respected ──────────────────────────────────────
# Validates the db_port variable flows through to the SG rules.
# Ensures future support for non-PostgreSQL databases (e.g. MySQL port 3306).

run "custom_db_port" {
  command = plan

  variables {
    vpc_id             = "vpc-mock00003"
    environment        = "prod-apac"
    db_port            = 3306 # MySQL
    regional_vpc_cidrs = []
    central_vpc_cidr   = "10.0.0.0/16"
  }

  assert {
    condition     = length(aws_security_group.db) == 1
    error_message = "DB SG should be created regardless of port"
  }
}

# ── Test 6: failover_vpc_cidr adds a SECOND ingress rule to DB SG ─────────────
# When the failover central VPC CIDR is provided, the DB SG must allow ingress
# from BOTH the primary (10.0.0.0/16) AND failover (10.5.0.0/16) CIDRs.
# Without this, the failover API has VPC Peering connectivity but the SG
# silently drops all database connection attempts during a failover.

run "failover_cidr_adds_second_db_sg_ingress" {
  command = plan

  variables {
    vpc_id             = "vpc-mock00002"
    environment        = "prod-eu"
    db_port            = 5432
    regional_vpc_cidrs = []
    central_vpc_cidr   = "10.0.0.0/16"
    failover_vpc_cidr  = "10.5.0.0/16"
  }

  assert {
    condition     = length(aws_security_group.db) == 1
    error_message = "DB SG must still be created when failover_vpc_cidr is provided"
  }
}

# ── Test 7: No failover_vpc_cidr — DB SG is backward compatible ───────────────
# Existing regional environments that don't set failover_vpc_cidr must continue
# to work. The dynamic ingress block must produce zero extra rules when the
# variable is empty (the default).

run "empty_failover_cidr_is_backward_compatible" {
  command = plan

  variables {
    vpc_id             = "vpc-mock00003"
    environment        = "prod-ca"
    db_port            = 5432
    regional_vpc_cidrs = []
    central_vpc_cidr   = "10.0.0.0/16"
    failover_vpc_cidr  = "" # default — no failover CIDR
  }

  assert {
    condition     = length(aws_security_group.db) == 1
    error_message = "DB SG must be created even without failover_vpc_cidr"
  }
}
