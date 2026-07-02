# ─────────────────────────────────────────────────────────────────────────────
# providers.tf — Stub providers for standalone terraform validate only.
#
# When this module is consumed by environments/central/ the caller passes:
#   providers = { aws = aws, aws.accepter = aws.eu }
# and these stub blocks are ignored entirely.
#
# Without this file, `terraform validate` fails in isolation because it can't
# resolve resources that reference aws.accepter — a known Terraform limitation
# for modules that require aliased providers via configuration_aliases.
# ─────────────────────────────────────────────────────────────────────────────

provider "aws" {
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  access_key                  = "mock"
  secret_key                  = "mock"
}

provider "aws" {
  alias                       = "accepter"
  region                      = "eu-west-1"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  access_key                  = "mock"
  secret_key                  = "mock"
}
