# ─────────────────────────────────────────────────────────────────────────────
# Module: vpc_peering
#
# Creates a cross-account, cross-region VPC Peering connection between the
# central API VPC (requester) and one regional VPC (accepter), then adds the
# necessary routes on both sides.
#
# Why VPC Peering over Transit Gateway:
#   • Point-to-point — no transitive routing means regional VPCs can NEVER
#     talk to each other, satisfying data-residency isolation requirements.
#   • No transit attachment fees (~$0.05/hr/attachment saved per region).
#   • Simpler blast radius: a misconfigured route table cannot accidentally
#     route EU traffic through a US gateway.
#
# Limitations acknowledged:
#   • Does not scale beyond ~125 peering connections per VPC.
#   • Adding a new region requires a new peering + route table entries.
#     (Acceptable for Protex's current 4-region footprint.)
#
# Usage: instantiate once per region from the central environment root module.
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      # Declares that this module requires both a default aws provider
      # AND an aliased aws.accepter provider — passed in by the caller.
      configuration_aliases = [aws.accepter]
    }
  }
}


locals {
  common_tags = merge(var.tags, {
    ManagedBy        = "terraform"
    Module           = "vpc_peering"
    PeeringName      = var.peering_name
    RequesterRegion  = var.requester_region
    RequesterAccount = var.requester_account_id
  })
}

# ── Step 1: Request the peering connection (runs in the central/requester account) ──

resource "aws_vpc_peering_connection" "this" {
  vpc_id        = var.requester_vpc_id
  peer_vpc_id   = var.accepter_vpc_id
  peer_region   = var.accepter_region
  peer_owner_id = var.accepter_account_id

  # auto_accept cannot be true for cross-account peering; the accepter must
  # explicitly accept via aws_vpc_peering_connection_accepter below.
  auto_accept = false

  tags = merge(local.common_tags, {
    Name = var.peering_name
    Side = "requester"
  })
}

# ── Step 2: Accept the peering connection (runs in the regional/accepter account) ──
# This resource must use a provider aliased to the accepter account + region.

resource "aws_vpc_peering_connection_accepter" "this" {
  provider                  = aws.accepter
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
  auto_accept               = true

  tags = merge(local.common_tags, {
    Name = var.peering_name
    Side = "accepter"
  })
}

# ── Step 3: Modify peering options ────────────────────────────────────────────
# Enable DNS resolution across the peering so the central API can resolve
# regional RDS endpoint hostnames to their private IPs.

resource "aws_vpc_peering_connection_options" "requester" {
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  depends_on = [aws_vpc_peering_connection_accepter.this]
}

resource "aws_vpc_peering_connection_options" "accepter" {
  provider                  = aws.accepter
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  depends_on = [aws_vpc_peering_connection_accepter.this]
}

# ── Step 4: Add routes on the REQUESTER side (central → regional) ─────────────
# One route per route table in the requester VPC pointing to the accepter CIDR.

resource "aws_route" "requester_to_accepter" {
  count                     = length(var.requester_route_table_ids)
  route_table_id            = var.requester_route_table_ids[count.index]
  destination_cidr_block    = var.accepter_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id

  depends_on = [aws_vpc_peering_connection_accepter.this]
}

# ── Step 5: Add return routes on the ACCEPTER side (regional → central) ───────
# Without these, traffic from the regional VPC cannot reach the central API.

resource "aws_route" "accepter_to_requester" {
  provider                  = aws.accepter
  count                     = length(var.accepter_route_table_ids)
  route_table_id            = var.accepter_route_table_ids[count.index]
  destination_cidr_block    = var.requester_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id

  depends_on = [aws_vpc_peering_connection_accepter.this]
}
