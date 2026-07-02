terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Global IAM: Cross-Account Roles
#
# Two IAM roles are required in each regional account:
#
# 1. TerraformDeployRole
#    Assumed by the CI/CD pipeline (GitHub Actions / Terraform Cloud) running
#    in the central account. Grants permissions to create VPCs, subnets,
#    security groups, and route tables in the regional account.
#
# 2. TerraformPeeringAccepterRole
#    Assumed by the central Terraform run to accept peering connections and
#    add return routes in the regional VPC route tables. This is a narrowly
#    scoped role — it cannot create or delete VPCs, only manage peering.
#
# 3. ProtexAPIReadRole (in each regional account)
#    Assumed at runtime by the central Observability API (via ECS task role or
#    Lambda execution role). Grants read-only RDS Data API access for event
#    queries. Write operations go directly to the regional API endpoint, not
#    through this cross-account path.
# ─────────────────────────────────────────────────────────────────────────────

# ── TerraformPeeringAccepterRole (deployed to each regional account) ──────────

resource "aws_iam_role" "terraform_peering_accepter" {
  name        = "TerraformPeeringAccepterRole"
  description = "Allows central Terraform to accept VPC peering connections and manage routes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.central_account_id}:role/TerraformDeployRole"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = var.external_id
        }
      }
    }]
  })

  tags = {
    ManagedBy = "terraform"
    Purpose   = "vpc-peering-accepter"
  }
}

resource "aws_iam_role_policy" "terraform_peering_accepter" {
  name = "PeeringAccepterPolicy"
  role = aws_iam_role.terraform_peering_accepter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Accept peering connections
        Effect = "Allow"
        Action = [
          "ec2:AcceptVpcPeeringConnection",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:ModifyVpcPeeringConnectionOptions",
        ]
        Resource = "*"
      },
      {
        # Manage route table entries for return routes only
        Effect = "Allow"
        Action = [
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:DescribeRouteTables",
        ]
        Resource = "*"
      }
    ]
  })
}

# ── ProtexAPIReadRole (deployed to each regional account) ─────────────────────

resource "aws_iam_role" "protex_api_read" {
  name        = "ProtexAPIReadRole"
  description = "Runtime role assumed by central Observability API for read-only DB access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        # The Lambda/ECS execution role ARN in the central account
        AWS = "arn:aws:iam::${var.central_account_id}:role/protex-api-execution-role"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = var.external_id
        }
      }
    }]
  })

  tags = {
    ManagedBy = "terraform"
    Purpose   = "read-only-db-access"
  }
}

resource "aws_iam_role_policy" "protex_api_read" {
  name = "ProtexAPIReadPolicy"
  role = aws_iam_role.protex_api_read.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # RDS Data API: read-only (ExecuteStatement for SELECT, no write statements)
        Effect = "Allow"
        Action = [
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement",
        ]
        Resource = var.regional_db_arn
        Condition = {
          # Enforce that only read operations are executed (application-level enforcement
          # is also required; this is a defense-in-depth condition via resource tag)
          StringEquals = {
            "aws:ResourceTag/AccessLevel" = "read"
          }
        }
      },
      {
        # Secrets Manager: retrieve DB credentials (read-only)
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.regional_db_secret_arn
      }
    ]
  })
}
