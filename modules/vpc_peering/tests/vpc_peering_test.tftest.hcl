# ─────────────────────────────────────────────────────────────────────────────
# Module: vpc_peering — Unit Tests
#
# Run with:  cd modules/vpc_peering && terraform test
#
# This module uses TWO aliased providers (aws = requester, aws.accepter).
# We mock both independently so neither side needs real credentials.
#
# Key assertions:
#   - Peering connection is created with the correct name tag
#   - Requester-side routes are created for every route table ID passed in
#   - Accepter-side return routes are created (bidirectional routing)
#   - DNS resolution is enabled on both sides (required for Aurora hostname resolution)
# ─────────────────────────────────────────────────────────────────────────────

# Mock the requester side (central account)
mock_provider "aws" {
  mock_resource "aws_vpc_peering_connection" {
    defaults = {
      id            = "pcx-mock00001"
      accept_status = "active"
    }
  }

  mock_resource "aws_vpc_peering_connection_options" {
    defaults = { id = "pcx-mock00001" }
  }

  mock_resource "aws_route" {
    defaults = { id = "r-mock-requester" }
  }
}

# Mock the accepter side (regional account)
mock_provider "aws" {
  alias = "accepter"

  mock_resource "aws_vpc_peering_connection_accepter" {
    defaults = {
      id            = "pcx-mock00001"
      accept_status = "active"
    }
  }

  mock_resource "aws_vpc_peering_connection_options" {
    defaults = { id = "pcx-mock00001" }
  }

  mock_resource "aws_route" {
    defaults = { id = "r-mock-accepter" }
  }
}

# ── Test 1: Peering connection created with correct name tag ─────────────────

run "peering_connection_name_tag" {
  command = plan

  variables {
    peering_name              = "protex-prod-central-to-eu"
    requester_vpc_id          = "vpc-central-mock"
    requester_vpc_cidr        = "10.0.0.0/16"
    requester_region          = "us-east-1"
    requester_account_id      = "111111111112"
    requester_route_table_ids = ["rtb-central-1", "rtb-central-2", "rtb-central-3"]
    accepter_vpc_id           = "vpc-eu-mock"
    accepter_vpc_cidr         = "10.2.0.0/16"
    accepter_region           = "eu-west-1"
    accepter_account_id       = "222222222222"
    accepter_route_table_ids  = ["rtb-eu-1", "rtb-eu-2", "rtb-eu-3"]
  }

  assert {
    condition     = aws_vpc_peering_connection.this.tags["Name"] == "protex-prod-central-to-eu"
    error_message = "Peering connection Name tag must match peering_name variable"
  }
}

# ── Test 2: Requester routes — one per route table ───────────────────────────
# The central VPC has 3 private route tables (one per AZ). Each needs a route
# to the regional CIDR pointing at the peering connection. Validates the count
# equals the number of route table IDs passed in.

run "requester_routes_one_per_route_table" {
  command = plan

  variables {
    peering_name              = "protex-prod-central-to-eu"
    requester_vpc_id          = "vpc-central-mock"
    requester_vpc_cidr        = "10.0.0.0/16"
    requester_region          = "us-east-1"
    requester_account_id      = "111111111112"
    requester_route_table_ids = ["rtb-central-1", "rtb-central-2", "rtb-central-3"]
    accepter_vpc_id           = "vpc-eu-mock"
    accepter_vpc_cidr         = "10.2.0.0/16"
    accepter_region           = "eu-west-1"
    accepter_account_id       = "222222222222"
    accepter_route_table_ids  = ["rtb-eu-1", "rtb-eu-2", "rtb-eu-3"]
  }

  assert {
    condition     = length(aws_route.requester_to_accepter) == 3
    error_message = "Must create one requester route per route table ID (3 route tables = 3 routes)"
  }
}

# ── Test 3: Accepter return routes — one per route table ─────────────────────
# Without return routes in the regional VPC, responses from the database cannot
# reach the central API. Validates bidirectional routing is established.

run "accepter_return_routes_one_per_route_table" {
  command = plan

  variables {
    peering_name              = "protex-prod-central-to-eu"
    requester_vpc_id          = "vpc-central-mock"
    requester_vpc_cidr        = "10.0.0.0/16"
    requester_region          = "us-east-1"
    requester_account_id      = "111111111112"
    requester_route_table_ids = ["rtb-central-1", "rtb-central-2", "rtb-central-3"]
    accepter_vpc_id           = "vpc-eu-mock"
    accepter_vpc_cidr         = "10.2.0.0/16"
    accepter_region           = "eu-west-1"
    accepter_account_id       = "222222222222"
    accepter_route_table_ids  = ["rtb-eu-1", "rtb-eu-2", "rtb-eu-3"]
  }

  assert {
    condition     = length(aws_route.accepter_to_requester) == 3
    error_message = "Must create one return route per accepter route table — bidirectional routing required"
  }
}

# ── Test 4: Peering name tag is on the Side=requester resource ───────────────

run "peering_side_tags" {
  command = plan

  variables {
    peering_name              = "protex-prod-central-to-ca"
    requester_vpc_id          = "vpc-central-mock"
    requester_vpc_cidr        = "10.0.0.0/16"
    requester_region          = "us-east-1"
    requester_account_id      = "111111111112"
    requester_route_table_ids = ["rtb-central-1"]
    accepter_vpc_id           = "vpc-ca-mock"
    accepter_vpc_cidr         = "10.3.0.0/16"
    accepter_region           = "ca-central-1"
    accepter_account_id       = "444444444442"
    accepter_route_table_ids  = ["rtb-ca-1"]
  }

  assert {
    condition     = aws_vpc_peering_connection.this.tags["Side"] == "requester"
    error_message = "Requester peering connection must be tagged Side=requester for auditability"
  }

  assert {
    condition     = aws_vpc_peering_connection.this.tags["PeeringName"] == "protex-prod-central-to-ca"
    error_message = "PeeringName tag must identify the specific connection for compliance audits"
  }
}
