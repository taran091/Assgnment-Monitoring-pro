region_label   = "eu"
eu_account_id  = "222222222222"

central_vpc_cidr  = "10.0.0.0/16"
failover_vpc_cidr = "10.5.0.0/16"

single_nat_gateway      = false
flow_log_retention_days = 90

# Populate after environments/central has been applied
central_alarm_sns_topic_arn = "arn:aws:sns:eu-west-1:111111111112:protex-network-alarms"

# Populate with pre-existing Aurora cluster details
aurora_cluster_identifier = "protex-eu-aurora-cluster"
aurora_db_endpoint        = "protex-eu-aurora-cluster.cluster-xxxxxxxxxxxx.eu-west-1.rds.amazonaws.com"
