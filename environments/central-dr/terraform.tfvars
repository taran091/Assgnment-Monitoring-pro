central_account_id = "111111111112"

single_nat_gateway      = false
flow_log_retention_days = 90

eu_account_id              = "222222222222"
eu_vpc_id                  = "vpc-eu-placeholder"
eu_vpc_cidr                = "10.2.0.0/16"
eu_private_route_table_ids = ["rtb-eu-1", "rtb-eu-2", "rtb-eu-3"]

us_account_id              = "333333333333"
us_vpc_id                  = "vpc-us-placeholder"
us_vpc_cidr                = "10.1.0.0/16"
us_private_route_table_ids = ["rtb-us-1", "rtb-us-2", "rtb-us-3"]

ca_account_id              = "444444444444"
ca_vpc_id                  = "vpc-ca-placeholder"
ca_vpc_cidr                = "10.3.0.0/16"
ca_private_route_table_ids = ["rtb-ca-1", "rtb-ca-2", "rtb-ca-3"]

apac_account_id              = "555555555555"
apac_vpc_id                  = "vpc-apac-placeholder"
apac_vpc_cidr                = "10.4.0.0/16"
apac_private_route_table_ids = ["rtb-apac-1", "rtb-apac-2", "rtb-apac-3"]
