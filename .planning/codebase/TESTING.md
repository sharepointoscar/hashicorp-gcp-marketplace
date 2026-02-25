# Testing Patterns

**Analysis Date:** 2025-02-24

## Test Framework

**Runner:**
- Kubernetes Apps (Click-to-Deploy): `mpdev` (Google Cloud Marketplace tools) - containerized validator
- VM Solutions (Terraform): `cft` (Cloud Foundation Toolkit) for metadata validation + `terraform` for IaC validation
- Shell scripts: Manual testing via bash execution with captured exit codes

**Assertion Library:**
- Not applicable (not a code testing framework repository)
- Instead, tools validate against external standards: GCP Marketplace schema validation, Terraform HCL syntax

**Run Commands:**
```bash
# Standard Kubernetes product validation (CANONICAL WORKFLOW)
REGISTRY=us-docker.pkg.dev/$PROJECT_ID/<product>-marketplace TAG=<version> \
  ./shared/scripts/validate-marketplace.sh <product>

# Kubernetes product only (no full validation)
cd products/<product> && make app/verify

# VM Solution (Boundary) validation
cd products/boundary && make validate/full

# Terraform module validation only
cd products/boundary && terraform validate

# CFT metadata validation (requires CFT CLI installed)
cd products/boundary && cft blueprint metadata -p . -v
```

## Test File Organization

**Location:**
- Kubernetes apps: Test deployment code in `apptest/deployer/` directory
- VM Solutions: Test variables in `marketplace_test.tfvars` + optional validation scripts in `scripts/`
- Shared validation: `shared/scripts/validate-marketplace.sh` (primary entry point for all K8s products)
- Test-specific schemas: `apptest/deployer/schema.yaml` with default values

**Naming:**
- Test deployment manifests: `apptest/deployer/manifest/tester.yaml.template`
- Test schema: `apptest/deployer/schema.yaml`
- Integration test scripts: `products/<product>/scripts/post-deploy-test.sh`
- Validation scripts: `products/<product>/scripts/validate-deployment.sh`

**Structure:**
```
products/<product>/
├── schema.yaml                          # User-facing deployment parameters
├── apptest/deployer/
│   ├── Dockerfile                       # Test container image
│   ├── schema.yaml                      # Test defaults (auto-populates UI)
│   └── manifest/
│       ├── tester.yaml.template         # Test pod/job definition
│       └── [other test resources]
└── scripts/
    ├── post-deploy-test.sh              # Application verification tests
    └── validate-deployment.sh            # Infrastructure validation
```

## Test Structure

**Kubernetes App Test Pattern:**
```bash
#!/bin/bash
# mpdev verify orchestration (from shared/scripts/validate-marketplace.sh)

# Phase 1: Prerequisites check
check_prerequisites  # Docker, gcloud, kubectl

# Phase 2: mpdev doctor check
mpdev doctor

# Phase 3: Build images
make REGISTRY="$REGISTRY" TAG="$TAG" MP_SERVICE_NAME="$MP_SERVICE_NAME" release

# Phase 4: Schema validation
mpdev /scripts/doctor.py --deployer="$DEPLOYER_IMAGE"

# Phase 5: Installation test
mpdev install --deployer="$DEPLOYER_IMAGE" --parameters="$PARAMS"

# Phase 6: Full verification
mpdev verify --deployer="$DEPLOYER_IMAGE" --parameters="$VERIFY_PARAMS"

# Phase 7: Vulnerability scanning
gcloud artifacts docker images describe "$IMAGE" --show-package-vulnerability
```

**VM Solution Test Pattern (Boundary):**
```bash
# Phase 1: Terraform validation
terraform init -backend=false
terraform validate

# Phase 2: CFT metadata validation
cft blueprint metadata -p . -v

# Phase 3: Terraform plan
terraform plan -var-file=marketplace_test.tfvars -var="project_id=$PROJECT_ID"

# Phase 4: Full deployment
terraform apply -var-file=marketplace_test.tfvars -var="project_id=$PROJECT_ID" -auto-approve

# Phase 5: Infrastructure verification
scripts/validate-deployment.sh  # SSH to VMs, check service status

# Phase 6: Cleanup
terraform destroy -var-file=marketplace_test.tfvars -var="project_id=$PROJECT_ID"
```

**Post-Deployment Test Pattern:**
- Location: `products/<product>/scripts/post-deploy-test.sh` (optional)
- Purpose: Verify application functionality after deployment
- Example (Boundary): Check controller health endpoint, verify workers registered
- Uses kubectl/gcloud to inspect running infrastructure

## Mocking

**Framework:**
- Not applicable (infrastructure validation, not unit testing)
- External services mocked via:
  - Fake reporting secrets (base64-encoded JSON blobs from Google's test vectors)
  - Marketplace license environment variables (provided by user)
  - Cloud SQL mocked via local test instance (when needed)

**Patterns:**
```bash
# Fake reporting secret creation in validate-marketplace.sh
cat <<'EOSECRET' | sed "s/\${SECRET_NAME}/fake-reporting-secret/" | kubectl apply -n "$TEST_NAMESPACE" -f - || true
apiVersion: v1
metadata:
  name: ${SECRET_NAME}
data:
  consumer-id: cHJvamVjdDpwci0yNWQ4ZmU0ZWE1M2I1Zjk=
  entitlement-id: ZmYzMDU1ZmYtZmZhMi00YTYyLThjNGEtZmJjNmFjMjE0Mjgx
  reporting-key: [base64-encoded key]
kind: Secret
type: Opaque
EOSECRET

# License parameter injection (from marketplace_test.tfvars)
license_secret_id = "projects/$PROJECT_ID/secrets/boundary-license/versions/latest"

# Test parameters passed to mpdev
mpdev install --parameters='{"name": "vault", "vaultLicense": "'"$(cat vault.hclic)"'"}'
```

**What to Mock:**
- GCP Marketplace reporting/entitlement secrets (provided by Google)
- Enterprise licenses (provided by user during deployment)
- Cloud DNS records (created only if `create_cloud_dns_record = true`)
- TLS certificates (auto-generated if not provided)

**What NOT to Mock:**
- Cloud SQL database (must be real for schema validation)
- Service accounts and IAM bindings (must be real for permission testing)
- Cloud KMS keys (must be real for encryption operations)
- VPC and networking (must be real for connectivity tests)

## Fixtures and Factories

**Test Data:**
```hcl
# From products/boundary/marketplace_test.tfvars
project_id                = "ibm-software-mp-project-test"
region                    = "us-central1"
boundary_fqdn             = "boundary.example.com"
license_file_path         = "./boundary.hclic"
boundary_version          = "0.21.0+ent"
friendly_name_prefix      = "mp"
vpc_name                  = "default"
controller_subnet_name    = "default"
```

**Vault Test Schema Defaults (apptest/deployer/schema.yaml):**
```yaml
publishedVersion: '1.21.0'
applicationApiVersion: v1beta1
properties:
  name:
    type: string
    default: 'vault-mp-test'
  namespace:
    type: string
    default: 'apptest-vault'
  replicas:
    type: integer
    default: 3
  reportingSecret:
    type: string
    default: 'fake-reporting-secret'
  vaultLicense:
    type: string
    default: ''  # Provided by validate-marketplace.sh
```

**Location:**
- Terraform test variables: `products/<product>/marketplace_test.tfvars`
- Kubernetes test defaults: `apptest/deployer/schema.yaml`
- License files: `products/<product>/*.hclic` (auto-detected by scripts)
- Credentials: `test/boundary-init-creds.txt` (generated during deployment)

## Coverage

**Requirements:**
- Kubernetes Apps: All schema properties tested via mpdev (required by Google Marketplace)
- VM Solutions: All Terraform variables exercised during plan/apply
- No coverage reporting tools integrated (implicit coverage via end-to-end validation)

**View Coverage:**
```bash
# Kubernetes: mpdev verify reports which schema properties were tested
REGISTRY=... TAG=... ./shared/scripts/validate-marketplace.sh <product>

# VM Solutions: terraform plan shows all resources to be created
terraform plan -var-file=marketplace_test.tfvars

# View full validation output with logs
REGISTRY=... TAG=... ./shared/scripts/validate-marketplace.sh <product> --keep-deployment
```

## Test Types

**Unit Tests:**
- Not used in this codebase
- Makefile targets are not unit-testable (they invoke external tools)
- Shell functions tested implicitly via script execution

**Integration Tests:**
- Primary test type for this repository
- Scope: Verify complete deployment pipeline (build → schema validation → install → verify)
- Approach: `validate-marketplace.sh` orchestrates full pipeline sequentially
- Example flow: docker build → mpdev doctor → mpdev install → mpdev verify → vulnerability scan

**E2E Tests:**
- Kubernetes: `mpdev verify` tests full application lifecycle (install → verify → uninstall)
- VM Solutions: `terraform apply` → infrastructure validation → health checks → cleanup
- Manual tests: SSH to deployed VMs, check service status, verify functionality
- Example (Boundary): Check controller health endpoint, list workers, verify DB connection

**Framework:**
- Kubernetes: `mpdev` (Google Cloud Marketplace validation tool)
- VM Solutions: `terraform validate` + `cft blueprint metadata`
- Custom scripts: Bash validation scripts in `scripts/` directories

## Common Patterns

**Async Testing:**
- Terraform: `terraform apply` is synchronous; waits for all resources to be ready
- Kubernetes: mpdev waits for pod readiness before considering install complete
- Health checks: Post-deploy scripts check readiness (e.g., HTTP health endpoints)

**Explicit Wait Pattern (Boundary deployment):**
```bash
# From deploy-with-logging.sh
run_deployment() {
    print_step "DEPLOY" "Running: make terraform/apply"
    print_warning "This phase typically takes 20-40 minutes"

    if make terraform/apply 2>&1 | tee "$log_file"; then
        print_success "Deployment completed"
    else
        print_error "Deployment failed"
        exit 1
    fi
}
```

**Error Testing:**
```bash
# Validation errors caught by terraform validate
terraform validate || {
    print_error "Terraform validation failed"
    exit 1
}

# Schema validation errors from mpdev
mpdev /scripts/doctor.py --deployer="$DEPLOYER_IMAGE" || true
# Note: `|| true` because mpdev doctor warnings don't fail validation

# Exit code checks for conditional behavior
if make validate/full 2>&1 | tee "$log_file"; then
    echo "success"
else
    exit_code=$?
    echo "failed with code $exit_code"
fi
```

## Test Lifecycle

**Setup:**
```bash
# Environment setup (shared/scripts/validate-marketplace.sh)
check_prerequisites          # Verify docker, gcloud, kubectl
check_mpdev                  # Ensure mpdev available (create wrapper if needed)
cd "$PRODUCT_DIR"            # Change to product directory
load_product_config          # Parse product.yaml for version
```

**Teardown:**
```bash
# Namespace cleanup (explicit, optional)
kubectl delete namespace "$TEST_NAMESPACE" --ignore-not-found --wait=false

# Force cleanup if stuck
kubectl delete ns "$TEST_NAMESPACE" --grace-period=0 --force

# PV cleanup (orphaned after namespace deletion)
kubectl patch pv "$pv" -p '{"metadata":{"finalizers":null}}' --type=merge
kubectl delete pv "$pv" --force --grace-period=0

# Full resource cleanup for Kubernetes products
./shared/scripts/validate-marketplace.sh <product> --cleanup
```

**Cleanup Function Pattern (Boundary):**
```bash
# From deploy-with-logging.sh - full cleanup
run_cleanup() {
    if [[ "$DESTROY_EXISTING" == "false" ]]; then
        return 0
    fi

    print_phase 2 "Cleanup (Destroying Existing Deployment)"
    make terraform/destroy 2>&1 | tee "$log_file"
}

# Terraform cleanup is automatic via state
terraform destroy -var-file=marketplace_test.tfvars -var="project_id=$PROJECT_ID" -auto-approve
```

## Continuous Validation

**Manual Validation Workflow (Standard):**
1. User runs `validate-marketplace.sh` for Kubernetes products
2. User runs `make validate/full` for VM Solutions
3. Scripts capture all output to timestamped log files
4. Logs reviewed for failures and vulnerability scans

**Log Collection:**
- Location: `products/boundary/logs/deployment-YYYYMMDD-HHMMSS/`
- Files: `01-validate.log`, `02-terraform-apply.log`, `03-infrastructure-validation.log`, etc.
- Summary: `deployment-summary.json` with phase durations and exit codes
- Full log: `full-deployment.log` (combined from all phases)

**Deployment Logging (Boundary):**
```bash
# From deploy-with-logging.sh - phase structure
print_phase 1 "Validation"
# Phase 1 execution, log to 01-validate.log

print_phase 2 "Cleanup (Destroying Existing Deployment)"
# Phase 2 execution, log to 02a-terraform-destroy.log

print_phase 3 "Deployment"
# Phase 3 execution, log to 02-terraform-apply.log
# Takes 20-40 minutes

print_phase 4 "Infrastructure Validation"
# Phase 4 execution, log to 03-infrastructure-validation.log

print_phase 5 "Post-Deployment Testing"
# Phase 5 execution, log to 04-post-deploy-test.log
```

## Test Isolation

**Kubernetes App Isolation:**
- Namespace isolation: Each test uses distinct test namespace (e.g., `vault-mp-test-<timestamp>`)
- Secrets isolation: Each namespace gets `fake-reporting-secret`
- PVC isolation: StatefulSets create isolated PersistentVolumeClaims per namespace
- Cleanup: All namespaces deleted after testing (or kept with `--keep-deployment`)

**VM Solution Isolation:**
- Terraform state isolation: Each deployment has separate `terraform.tfstate` file
- Resource naming: GCP Marketplace deployment name (`goog_cm_deployment_name`) ensures unique resource names
- Network isolation: Separate VPCs or subnets can be specified
- Cleanup: `terraform destroy` removes all resources created by state

## Validation Requirements

**GCP Marketplace Kubernetes Requirements (Google tests):**
1. Installation must succeed: All resources applied and healthy
2. Functionality tests must pass: Tester pod exits with status 0
3. Uninstallation must succeed: All resources cleanly removed
4. Google uses GKE 1.33 and 1.35 for testing

**GCP Marketplace VM Solution Requirements:**
1. CFT metadata must validate: `cft blueprint metadata -p . -v` passes
2. Terraform must validate: `terraform validate` succeeds
3. Producer Portal validates blueprint (up to 2 hours)
4. Deployment preview testing available for manual verification

**Security Requirements:**
- Container images must be scanned for vulnerabilities
- High/Critical CVEs must be addressed before submission
- Image annotations required: `com.googleapis.cloudmarketplace.product.service.name`

---

*Testing analysis: 2025-02-24*
