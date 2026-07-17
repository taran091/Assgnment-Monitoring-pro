# Protex Man-in-the-Middle Observability Platform

Terraform infrastructure for the AI centralised observability platform.
Grafana (AMG) connects directly to four regional Aurora PostgreSQL databases
(EU, US, CA, APAC) via VPC Peering — no intermediate API, no custom application code.

---

## Repository Structure

```
protex-simple/
├── environments/
│   ├── central/            ← Hub: AMP + Grafana + VPC Peering (eu-west-1)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   ├── central-dr/         ← DR warm standby (us-east-1, same account)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   ├── eu/                 ← EU regional VPC + Aurora SG + monitoring
│   ├── us/                 ← US regional VPC + Aurora SG + monitoring
│   ├── ca/                 ← CA regional VPC + Aurora SG + monitoring
│   └── apac/               ← APAC regional VPC + Aurora SG + monitoring
├── modules/
│   ├── networking/         ← Three-tier VPC (public/private/data), NAT GWs, Flow Logs
│   ├── vpc_peering/        ← Cross-account, cross-region peering lifecycle
│   ├── security_groups/    ← Least-privilege SGs (sg-api, sg-db with dual-CIDR)
│   ├── monitoring/         ← CloudWatch alarms, EventBridge peering rules, SNS
│   ├── observability/      ← AMP workspace, Grafana AMG, PostgreSQL data sources
│   ├── route53_failover/   ← Private hosted zone, health check, failover DNS records
│   ├── regional_monitoring/← Aurora alarms + connectivity probe Lambda (per region)
│   └── edge_monitoring/    ← AMP recording rules for Linux edge devices
└── global/
    └── iam/                ← Cross-account IAM roles (deployed once per regional account)
```

---

## Module Organisation

### modules/networking
Creates a three-tier VPC with one subnet per Availability Zone per tier (9 subnets total across 3 AZs):

| Tier | Subnet range | Purpose |
|---|---|---|
| Public | `.0–2.x/24` | NAT Gateway EIPs only. No application workloads. |
| Private | `.10–12.x/24` | Grafana AMG VPC config endpoints, Lambda functions |
| Data | `.20–22.x/24` | Aurora PostgreSQL clusters (regional VPCs only) |

**Key output:** `private_route_table_ids` — consumed by `vpc_peering` to inject bidirectional routes.

`single_nat_gateway = false` (default) deploys one NAT Gateway per AZ for HA. Set to `true` to reduce cost where HA is not required.

### modules/vpc_peering
Orchestrates the full cross-account VPC Peering lifecycle in **one Terraform apply** using aliased providers:

1. **Request** — central account sends peering request (`auto_accept = false` for cross-account)
2. **Accept** — regional account accepts via `aws.accepter` aliased provider (STS AssumeRole)
3. **DNS options** — enables private DNS resolution so Aurora hostnames resolve to private IPs
4. **Requester routes** — injects route in central route tables: `regional_cidr → peering_connection`
5. **Accepter return routes** — injects return route in regional route tables: `central_cidr → peering_connection`

**Important:** Return routes (step 5) are required. Without them, queries reach Aurora but responses cannot return — the connection silently hangs.

The `terraform` block declares `configuration_aliases = [aws.accepter]` which tells Terraform this module expects both `aws` and `aws.accepter` providers to be passed by the caller.

### modules/security_groups
Creates one of two security groups based on which variables are provided:

- **sg-api** (central, when `regional_vpc_cidrs` is set): egress only to port 5432 on regional VPC CIDRs
- **sg-db** (regional, when `central_vpc_cidr` is set): ingress port 5432 from central CIDR + optional `failover_vpc_cidr`

The `dynamic "ingress"` block adds a second rule when `failover_vpc_cidr = "10.5.0.0/16"` is set, enabling the DR Grafana instance to reach Aurora without any manual changes during failover.

### modules/observability
Provisions the full managed observability stack:

- **AMP workspace** — KMS encrypted, audit logs to CloudWatch, Alert Manager for Prometheus-based alerts
- **Grafana AMG** — AWS SSO auth, VPC configuration to reach private Aurora endpoints
- **PostgreSQL data sources** — one per regional Aurora, managed via the `grafana` Terraform provider
- **Recording rules** — pre-computed per-region metrics so dashboards load fast

The `grafana` provider authenticates using the AMG workspace API key created in the same apply.

### modules/monitoring
CloudWatch-based monitoring for AWS-native signals that are not available as Prometheus metrics:

- **EventBridge rules** — match `DeleteVpcPeeringConnection` and `RejectVpcPeeringConnection` CloudTrail events (fires within seconds)
- **CloudWatch alarms** — API latency p95, 5xx error rate, Route 53 health check status
- **SNS topic** — single destination for all alarms → PagerDuty P1/P2 + Slack

### modules/regional_monitoring
Deployed to each regional AWS account:

- **Aurora CloudWatch alarms** — DatabaseConnections, SelectLatency, AuroraReplicaLag, CPUUtilization
- **Connectivity probe Lambda** — runs every 60 seconds, attempts TCP connect to Aurora:5432, publishes `Protex/Connectivity::RegionalDBReachable` metric
- **CW alarm on probe metric** — `treat_missing_data = "breaching"` so a stopped probe also fires an alert

### modules/route53_failover
- **Private hosted zone** (`observability.protex.internal`) associated with both primary and DR VPCs
- **Route 53 health check** — polls Grafana AMG endpoint every 10 seconds
- **PRIMARY record** → primary Grafana (eu-west-1)
- **SECONDARY record** → DR Grafana (us-east-1) — activates automatically after 3 failures (~60s RTO)
- `prevent_destroy = true` on the hosted zone prevents accidental deletion

### modules/edge_monitoring
AMP recording rules and alert rules for Linux-based Protex edge devices:

- `protex:device_seconds_since_heartbeat` — liveness check from systemd heartbeat timer
- `protex:device_disk_free_gb` — video buffer disk space
- `protex:mqtt_failure_rate` — MQTT delivery failures
- `protex:inference_error_rate_1m` — AI model error rate

Prometheus Node Exporter + Protex app exporter on each device → Video Recorder Server → `remote_write` → AMP. See `modules/edge_monitoring/config/` for Prometheus and heartbeat configuration files.

### global/iam
Two IAM roles deployed **once per regional account** before any other environment:

- **TerraformPeeringAccepterRole** — allows central Terraform to accept peering connections and manage route table entries only
- **ProtexAPIReadRole** — allows Grafana to assume this role for Aurora read access (aps:RemoteWrite + RDS Data API read-only)

Both use `ExternalId` condition on `AssumeRole` to prevent confused-deputy attacks.

---

## CIDR Allocation

All CIDRs are non-overlapping — a hard requirement for VPC Peering.

| Environment | AWS Region | VPC CIDR | Role |
|---|---|---|---|
| central (primary) | eu-west-1 / Ireland | 10.0.0.0/16 | Hub — Grafana + AMP |
| eu | eu-west-1 | 10.2.0.0/16 | EU Aurora (GDPR) |
| us | us-west-2 | 10.1.0.0/16 | US Aurora |
| ca | ca-central-1 | 10.3.0.0/16 | CA Aurora (PIPEDA) |
| apac | ap-southeast-1 | 10.4.0.0/16 | APAC Aurora |
| central-dr | us-east-1 | 10.5.0.0/16 | DR warm standby (same account) |

---

## Deployment Order

Environments have dependencies — regional VPCs must exist before the central apply can establish peering connections.

### Prerequisites
- Terraform >= 1.7
- `TerraformDeployRole` in each AWS account, assumable by the CI identity
- S3 backend buckets and DynamoDB lock tables (run `global/iam` bootstrap first)

### Step 1: Deploy global IAM (once per regional account)
```bash
cd global/iam
terraform init
terraform apply
```
Creates `TerraformPeeringAccepterRole` and `ProtexAPIReadRole` in each regional account.

### Step 2: Deploy regional environments (can run in parallel)
```bash
# Run in parallel — no dependencies between regions
cd environments/eu   && terraform init && terraform plan  && terraform apply &
cd environments/us   && terraform init && terraform plan  && terraform apply &
cd environments/ca   && terraform init && terraform plan  && terraform apply &
cd environments/apac && terraform init && terraform plan  && terraform apply &
wait
```
Each creates a VPC, security groups, and regional monitoring. Outputs VPC ID and route table IDs.

### Step 3: Deploy DR environment
```bash
cd environments/central-dr
terraform init
terraform apply
```
Creates the DR VPC in us-east-1 with second set of peering connections pre-established.

### Step 4: Populate central/terraform.tfvars
Copy VPC IDs and route table IDs from regional outputs into `environments/central/terraform.tfvars`. In CI this is automated:
```bash
EU_VPC=$(cd environments/eu && terraform output -raw vpc_id)
# ... etc
```

### Step 5: Deploy central hub
```bash
cd environments/central
terraform init
terraform plan -out plan
terraform apply
```
Creates the central VPC, all 4 peering connections (request + accept in one apply using aliased providers), AMP workspace, Grafana AMG with PostgreSQL data sources, Route 53 failover, and all monitoring.

### Makefile shortcuts
```bash
make deploy-all      # full stack in dependency order
make deploy-regional # eu/us/ca/apac in parallel
make test            # 33 mock provider tests (no AWS credentials needed)
make validate        # syntax check all modules
make fmt             # auto-format all .tf files
```

---

## Configuration

All settings are plain variables in `terraform.tfvars` — no workspace switching needed:

```hcl
# environments/central/terraform.tfvars
single_nat_gateway       = false   # true = single shared NAT GW (cost saving)
flow_log_retention_days  = 90      # 365 for EU GDPR compliance
latency_threshold_ms     = 2000    # Grafana alert threshold
error_rate_threshold_pct = 1

eu_aurora_endpoint = "protex-eu-aurora.cluster-xxxx.eu-west-1.rds.amazonaws.com"
# Aurora passwords fetched from Secrets Manager at apply time
eu_aurora_password = "FETCH_FROM_SECRETS_MANAGER"
```

---

## Testing

33 mock provider tests across 6 modules. Zero AWS credentials required.

```bash
cd ~/Desktop/protex-simple
make test
```

Tests use Terraform's native `mock_provider` (Terraform 1.7+). Every AWS API call is intercepted and returns mocked values — no network access, no real resources created.

| Module | Tests | What's Covered |
|---|---|---|
| networking | 6 | Subnet counts, NAT GW count, flow log retention, tier tags |
| security_groups | 7 | SG creation logic, dual-CIDR failover ingress, custom port |
| vpc_peering | 4 | Name tags, bidirectional routes, side/PeeringName tags |
| monitoring | 4 | Alarm gating, EventBridge rules per peering, threshold values |
| route53_failover | 6 | Health check timing, PRIMARY/SECONDARY DNS, CW alarm |
| regional_monitoring | 6 | Aurora metric names, connectivity probe Lambda, missing-data-breaching |

---

## Shared Modules

This project's `modules/` directory is the single source of truth. 
