# ─────────────────────────────────────────────────────────────────────────────
# Protex Observability (Simple) — Terraform Test Runner
#
# Prerequisites:
#   - Terraform >= 1.7  (mock_provider requires 1.7+)
#
# NO AWS credentials needed for any target — tests use mock_provider.
# ─────────────────────────────────────────────────────────────────────────────

MODULES := modules/networking modules/security_groups modules/vpc_peering modules/monitoring modules/observability modules/regional_monitoring modules/route53_failover modules/edge_monitoring

.PHONY: all validate test fmt fmt-check help

all: fmt-check validate test  ## Run all checks

# ── Validate ──────────────────────────────────────────────────────────────────
validate:  ## Check syntax and type-correctness of all modules (no AWS needed)
	@echo "\n▶ terraform validate (all modules)\n"
	@for m in $(MODULES); do \
		echo "  Validating $$m ..."; \
		(cd $$m && rm -rf .terraform .terraform.lock.hcl && terraform init -backend=false -input=false -no-color > /dev/null 2>&1 && terraform validate -no-color) || exit 1; \
	done
	@echo "\n✓ validate passed\n"

# ── Test ──────────────────────────────────────────────────────────────────────
test:  ## Run terraform test with mock providers — no AWS credentials needed
	@echo "\n▶ terraform test (mock providers)\n"
	@for m in modules/networking modules/security_groups modules/vpc_peering modules/monitoring modules/route53_failover modules/regional_monitoring; do \
		echo "  Testing $$m ..."; \
		(cd $$m && rm -rf .terraform .terraform.lock.hcl && terraform init -backend=false -input=false -no-color > /dev/null 2>&1 && terraform test -no-color) || exit 1; \
	done
	@echo "\n✓ all tests passed\n"

# Individual module targets
test-networking:          ## networking module tests only
	cd modules/networking && terraform test -verbose

test-security-groups:     ## security_groups module tests only
	cd modules/security_groups && terraform test -verbose

test-vpc-peering:         ## vpc_peering module tests only
	cd modules/vpc_peering && terraform test -verbose

test-monitoring:          ## monitoring module tests only
	cd modules/monitoring && terraform test -verbose

test-route53-failover:    ## route53_failover module tests only
	cd modules/route53_failover && terraform test -verbose

test-regional-monitoring: ## regional_monitoring module tests only
	cd modules/regional_monitoring && terraform test -verbose

# ── Format ────────────────────────────────────────────────────────────────────
fmt:        ## Auto-format all Terraform files
	terraform fmt -recursive

fmt-check:  ## Check formatting without modifying files (CI-safe)
	@echo "\n▶ terraform fmt -check\n"
	@terraform fmt -check -recursive -no-color
	@echo "\n✓ fmt check passed\n"

# ── Deploy ────────────────────────────────────────────────────────────────────
deploy-regional:  ## Deploy eu/us/ca/apac in parallel (no AWS dependencies on each other)
	@echo "Deploying regional environments in parallel..."
	@cd environments/eu   && terraform init && terraform apply -auto-approve &
	@cd environments/us   && terraform init && terraform apply -auto-approve &
	@cd environments/ca   && terraform init && terraform apply -auto-approve &
	@cd environments/apac && terraform init && terraform apply -auto-approve &
	@wait
	@echo "✓ All regional environments deployed"

deploy-dr:  ## Deploy central-dr (warm standby, us-east-1)
	cd environments/central-dr && terraform init && terraform apply -auto-approve

deploy-central:  ## Deploy primary central hub (requires regional outputs in terraform.tfvars)
	cd environments/central && terraform init && terraform apply -auto-approve

deploy-all: deploy-regional deploy-dr deploy-central  ## Deploy everything in order

# ── Help ──────────────────────────────────────────────────────────────────────
help:  ## Show available targets
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-26s\033[0m %s\n", $$1, $$2}'
	@echo ""

.DEFAULT_GOAL := help
