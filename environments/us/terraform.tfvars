region_label   = "us"
us_account_id  = "333333333333"

central_vpc_cidr  = "10.0.0.0/16"
failover_vpc_cidr = "10.5.0.0/16"

single_nat_gateway      = false
flow_log_retention_days = 90

# Populate after environments/central has been applied
central_alarm_sns_topic_arn = "arn:aws:sns:eu-west-1:111111111112:protex-network-alarms"

# Populate with pre-existing Aurora cluster details
aurora_cluster_identifier = "protex-us-aurora-cluster"
aurora_db_endpoint        = "protex-us-aurora-cluster.cluster-xxxxxxxxxxxx.us-west-2.rds.amazonaws.com"
