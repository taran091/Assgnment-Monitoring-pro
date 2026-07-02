# ── Central account ────────────────────────────────────────────────────────────
aws_region         = "eu-west-1"
central_account_id = "111111111112"
central_vpc_cidr   = "10.0.0.0/16"

# ── Workspace-replacement tunables ─────────────────────────────────────────────
# Adjust these directly instead of switching workspaces.
single_nat_gateway       = false
flow_log_retention_days  = 90
latency_threshold_ms     = 2000
error_rate_threshold_pct = 1

# ── EU regional account ────────────────────────────────────────────────────────
eu_account_id              = "222222222222"
eu_vpc_id                  = "vpc-eu-placeholder"
eu_vpc_cidr                = "10.2.0.0/16"
eu_private_route_table_ids = ["rtb-eu-1", "rtb-eu-2", "rtb-eu-3"]

# ── US regional account ────────────────────────────────────────────────────────
us_account_id              = "333333333333"
us_vpc_id                  = "vpc-us-placeholder"
us_vpc_cidr                = "10.1.0.0/16"
us_private_route_table_ids = ["rtb-us-1", "rtb-us-2", "rtb-us-3"]

# ── CA regional account ────────────────────────────────────────────────────────
ca_account_id              = "444444444444"
ca_vpc_id                  = "vpc-ca-placeholder"
ca_vpc_cidr                = "10.3.0.0/16"
ca_private_route_table_ids = ["rtb-ca-1", "rtb-ca-2", "rtb-ca-3"]

# ── APAC regional account ──────────────────────────────────────────────────────
apac_account_id              = "555555555555"
apac_vpc_id                  = "vpc-apac-placeholder"
apac_vpc_cidr                = "10.4.0.0/16"
apac_private_route_table_ids = ["rtb-apac-1", "rtb-apac-2", "rtb-apac-3"]

# ── Aurora endpoints for Grafana PostgreSQL data sources ───────────────────────
eu_aurora_endpoint   = "protex-eu-aurora-cluster.cluster-xxxx.eu-west-1.rds.amazonaws.com"
us_aurora_endpoint   = "protex-us-aurora-cluster.cluster-xxxx.us-west-2.rds.amazonaws.com"
ca_aurora_endpoint   = "protex-ca-aurora-cluster.cluster-xxxx.ca-central-1.rds.amazonaws.com"
apac_aurora_endpoint = "protex-apac-aurora-cluster.cluster-xxxx.ap-southeast-1.rds.amazonaws.com"
# Passwords fetched from Secrets Manager in production — placeholder here
eu_aurora_password   = "FETCH_FROM_SECRETS_MANAGER"
us_aurora_password   = "FETCH_FROM_SECRETS_MANAGER"
ca_aurora_password   = "FETCH_FROM_SECRETS_MANAGER"
apac_aurora_password = "FETCH_FROM_SECRETS_MANAGER"
