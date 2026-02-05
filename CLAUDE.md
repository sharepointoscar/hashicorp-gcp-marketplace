# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this monorepo.

## CRITICAL RULES - DO NOT VIOLATE

### NEVER Create Infrastructure Outside of Terraform

**VIOLATION ALERT**: When infrastructure is managed by Terraform, you must NEVER create, modify, or delete cloud resources using CLI commands (`gcloud`, `kubectl`, `aws`, etc.) or any other method outside of Terraform.

This applies to ALL products in this repository and includes but is not limited to:
- Cloud NAT / Cloud Routers
- Compute instances / GKE clusters
- Load balancers / Forwarding rules
- Firewall rules / Security groups
- Service accounts / IAM bindings
- KMS keys / Secrets
- Cloud SQL instances
- Storage buckets
- Any other cloud resource

**Why this is critical:**
1. Creates state drift between Terraform and actual infrastructure
2. Causes `terraform apply` failures with "already exists" errors
3. Makes resources unmanageable by Terraform
4. Requires manual cleanup or complex state manipulation to fix
5. Violates Infrastructure-as-Code principles
6. Wastes significant time debugging state issues

**Correct approach:**
- Add the resource to Terraform configuration
- Run `terraform apply` to create it
- Let Terraform manage the full lifecycle

**If a resource is needed urgently:**
- Ask the user if they want to add it to Terraform
- NEVER create it manually "just to test" or "to speed things up"

**Exception:** Read-only commands (e.g., `gcloud compute instances list`, `kubectl get pods`) are allowed for debugging and verification.

---

## Repository Overview

This is a **GCP Marketplace monorepo** for HashiCorp products. Each product in `products/` is a self-contained GCP Marketplace deployer that can be independently built, validated, and published.

## Standard Validation Workflow

**Always use the shared validation script for ALL Kubernetes products:**

```bash
REGISTRY=gcr.io/$PROJECT_ID TAG=<version> \
  ./shared/scripts/validate-marketplace.sh <product-name>
```

This runs the complete pipeline:
1. Prerequisites check + mpdev doctor
2. Build all images (`make release`)
3. Schema verification
4. mpdev install (test deployment)
5. mpdev verify (full verification)
6. Vulnerability scan check

**Script options:**
```bash
--keep-deployment    # Keep test deployment after validation (for debugging)
--cleanup            # Clean up all test namespaces and orphaned PVs, then exit
--gcr-clean          # Delete ALL existing GCR images before building
--cluster=<name>     # Specify GKE cluster name
--zone=<zone>        # Specify GKE zone
```

**Always provide image hashes** after running the workflow.

## Repository Structure

```
hashicorp-gcp-marketplace/
├── CLAUDE.md                        # This file - repo guidance
├── shared/                          # Shared build infrastructure
│   ├── Makefile.common              # Docker flags, print helpers
│   ├── Makefile.product             # Generic deployer/tester build rules
│   └── scripts/
│       ├── lib/
│       │   └── common.sh            # Shell functions (colors, docker_build_mp, etc.)
│       └── validate-marketplace.sh  # Standard validation script (entry point)
├── products/
│   ├── boundary/                    # Boundary Enterprise (VM Solution - Terraform)
│   ├── consul/                      # Consul Enterprise (Kubernetes App)
│   ├── terraform-cloud-agent/       # TFC Agent (Kubernetes App)
│   ├── terraform-enterprise/        # TFE (Kubernetes App - External Services)
│   └── vault/                       # Vault Enterprise (Kubernetes App - Integrated Storage)
```

**Note:** There is no root Makefile. Use `./shared/scripts/validate-marketplace.sh` for all K8s build/validation tasks. Boundary uses Terraform directly.

## Product Types

This repo contains two types of GCP Marketplace products:

### Kubernetes Apps (Click-to-Deploy)
- **Products**: Consul, Vault, Terraform Enterprise, Terraform Cloud Agent
- **Deployment**: GKE via mpdev (Click-to-Deploy)
- **Metadata**: `schema.yaml`
- **Validation**: `validate-marketplace.sh` → mpdev verify
- **Images**: Container images pushed to GCR/Artifact Registry

### VM Solutions (Terraform Blueprint)
- **Products**: Boundary
- **Deployment**: Compute Engine VMs via Terraform
- **Metadata**: `metadata.yaml` + `metadata.display.yaml` (CFT Blueprint)
- **Validation**: `cft blueprint metadata -p . -v`
- **Images**: VM binary installation (no container images)

## Product Architecture (Kubernetes Apps)

Each Kubernetes product follows this structure:

```
products/<product>/
├── Makefile                         # Product-specific build targets
├── schema.yaml                      # GCP Marketplace schema (user inputs)
├── product.yaml                     # Product metadata (id, version, partnerId)
├── CLAUDE.md                        # Product-specific guidance
├── *.hclic                          # Enterprise license (gitignored)
├── manifest/
│   ├── application.yaml.template    # GCP Marketplace Application CRD
│   └── manifests.yaml.template      # Kubernetes resources
├── deployer/
│   └── Dockerfile                   # Deployer image
├── apptest/deployer/
│   ├── Dockerfile                   # Tester image
│   ├── schema.yaml                  # Test schema with defaults
│   └── manifest/tester.yaml.template
└── images/
    └── <app>/Dockerfile             # Application image(s)
```

## Product Architecture (VM Solutions)

Boundary follows the CFT Blueprint structure:

```
products/boundary/
├── main.tf                          # Root module orchestration
├── variables.tf                     # Input variables
├── outputs.tf                       # Output values
├── versions.tf                      # Provider constraints
├── metadata.yaml                    # GCP Marketplace blueprint
├── metadata.display.yaml            # Marketplace UI configuration
├── CLAUDE.md                        # Product-specific guidance
├── modules/
│   ├── controller/                  # Controller VMs, Cloud SQL, KMS, LB
│   ├── worker/                      # Ingress/Egress workers
│   └── prerequisites/               # Secrets Manager setup
├── packer/                          # VM image builds (if needed)
└── test/                            # Test configurations
```

## Shared Infrastructure

### Makefile.common
- `PLATFORM`: linux/amd64 (required by GCP Marketplace)
- `DOCKER_BUILD_FLAGS`: --provenance=false --sbom=false --no-cache
- Print helpers: `print_notice`, `print_success`, `print_error`

### Makefile.product
Products must define:
- `APP_ID`: Product identifier (e.g., `vault`, `terraform-enterprise`)
- `MP_SERVICE_NAME`: GCP Marketplace service annotation

Provides generic rules for:
- `$(BUILD_DIR)/$(APP_ID)/deployer` - Deployer image build
- `$(BUILD_DIR)/$(APP_ID)/tester` - Tester image build
- `app/verify` - Run mpdev verify
- `app/install` - Run mpdev install
- `release` - Clean, build, push, tag with minor versions

### common.sh Library
- `print_step`, `print_success`, `print_error`, `print_warning` - Colored output
- `docker_build_mp` - Docker build with marketplace-compliant flags
- `load_product_config` - Parse product.yaml
- `check_prerequisites` - Verify docker, gcloud, kubectl installed
- `check_mpdev` - Ensure mpdev is available (creates wrapper if needed)

## Product Comparison

| Aspect | Terraform Enterprise | Vault | Consul | Boundary |
|--------|---------------------|-------|--------|----------|
| **Type** | Kubernetes App | Kubernetes App | Kubernetes App | VM Solution |
| **Storage Mode** | External (Cloud SQL, Redis, GCS) | Integrated (Raft) | Integrated (Raft) | External (Cloud SQL) |
| **Infrastructure** | Requires pre-provisioning | Self-contained | Self-contained | Terraform modules |
| **Registry Auth** | Required (images.releases.hashicorp.com) | Not required | Required | N/A (binary install) |
| **UBB Agent** | Custom build (security patches) | Pulled from Google | Custom build | N/A |
| **Complexity** | High (TLS, DB encoding, encryption) | Low (replicas, storage) | Medium (gossip, TLS) | High (KMS, workers, Cloud SQL) |

## Product-Specific Workflows

### Terraform Enterprise (Kubernetes)

**Prerequisites:**
```bash
docker login images.releases.hashicorp.com -u terraform -p $TFE_LICENSE
cd products/terraform-enterprise/terraform && terraform apply  # Pre-provision infra
```

**Validation:**
```bash
REGISTRY=gcr.io/$PROJECT_ID TAG=1.22.1 \
  ./shared/scripts/validate-marketplace.sh terraform-enterprise
```

**Key considerations:**
- DATABASE_URL requires URL-encoded password (`/` → `%2F`)
- ENC_PASSWORD must match TFE_ENCRYPTION_PASSWORD
- Clean vault tables between mpdev verify runs
- See `products/terraform-enterprise/CLAUDE.md`

### Vault (Kubernetes)

**Prerequisites:**
```bash
# Configure Artifact Registry auth
gcloud auth configure-docker us-docker.pkg.dev

# Place Enterprise license in product directory
cp /path/to/vault.hclic products/vault/
```

**Validation:**
```bash
REGISTRY=us-docker.pkg.dev/$PROJECT_ID/vault-marketplace TAG=1.21.0 \
  ./shared/scripts/validate-marketplace.sh vault
```

**Key considerations:**
- Uses Raft integrated storage (no external DB)
- Vault Enterprise images are on Docker Hub (no registry login needed)
- License auto-detected from *.hclic file
- UBB agent pulled directly from Google's registry
- See `products/vault/CLAUDE.md`

### Consul (Kubernetes)

**Prerequisites:**
```bash
cp /path/to/consul-license.hclic products/consul/
cd products/consul && make registry/login
```

**Validation:**
```bash
REGISTRY=gcr.io/$PROJECT_ID TAG=1.22.2 \
  ./shared/scripts/validate-marketplace.sh consul
```

**Key considerations:**
- License auto-detected from *.hclic file
- Requires gossip encryption key

### Boundary (VM Solution)

**Prerequisites:**
```bash
gcloud auth login && gcloud auth application-default login
gcloud secrets create boundary-license --data-file=boundary.hclic
```

**Validation:**
```bash
cd products/boundary
terraform init && terraform validate
cft blueprint metadata -p . -v  # Validate marketplace metadata
terraform plan -var project_id=$PROJECT_ID \
  -var boundary_fqdn="boundary.example.com" \
  -var boundary_license_secret="projects/$PROJECT_ID/secrets/boundary-license/versions/latest"
```

**Key considerations:**
- Uses HVD (HashiCorp Validated Design) modules
- Controllers in public subnet, workers span public/private
- Separate KMS keys for root, worker, recovery, BSR
- See `products/boundary/CLAUDE.md`

## GCP Marketplace Verification Requirements

### Kubernetes Apps
Apps are executed in Google's Verification system to ensure:
1. **Installation succeeds**: All resources applied and healthy
2. **Functionality tests pass**: Tester Pod exits with status 0
3. **Uninstallation succeeds**: All resources removed

**Google's test clusters run GKE versions 1.33 and 1.35** - ensure compatibility.

### VM Solutions
Terraform blueprints are validated via:
1. CFT metadata validation: `cft blueprint metadata -p . -v`
2. Producer Portal validation (up to 2 hours)
3. Deployment preview testing

## GCP Marketplace Image Requirements (Kubernetes)

All images must be:
- Single architecture: `linux/amd64`
- Docker V2 manifests: `--provenance=false --sbom=false`
- Annotated: `com.googleapis.cloudmarketplace.product.service.name=<MP_SERVICE_NAME>`
- Tagged with semver: `1.22.1` (full) and `1.22` (minor alias)

## Version Synchronization

### Kubernetes Products
These files must have matching versions:
1. `schema.yaml` → `publishedVersion`
2. `apptest/deployer/schema.yaml` → `publishedVersion`
3. `manifest/application.yaml.template` → `version`
4. `product.yaml` → `version`

### VM Solutions (Boundary)
These files must have matching versions:
1. `metadata.yaml` → `spec.info.version`
2. `variables.tf` → `boundary_version` default

## Adding a New Product

### Kubernetes App
1. Create directory: `products/<product-name>/`
2. Copy structure from existing product (vault is simpler template)
3. Create product-specific Makefile defining `APP_ID` and `MP_SERVICE_NAME`
4. Create `product.yaml` with id, version, partnerId, solutionId
5. Create schema.yaml with user inputs
6. Create manifest templates
7. Create Dockerfiles for app images
8. Create CLAUDE.md with product-specific guidance
9. Validate: `./shared/scripts/validate-marketplace.sh <product-name>`

### VM Solution
1. Create directory: `products/<product-name>/`
2. Create Terraform modules (main.tf, variables.tf, outputs.tf, versions.tf)
3. Create `metadata.yaml` (CFT Blueprint format)
4. Create `metadata.display.yaml` (UI configuration)
5. Create CLAUDE.md with product-specific guidance
6. Validate: `cft blueprint metadata -p . -v`

## Common Commands

```bash
# Validate any Kubernetes product (STANDARD WORKFLOW)
REGISTRY=gcr.io/$PROJECT_ID TAG=<version> \
  ./shared/scripts/validate-marketplace.sh <product>

# Cleanup all test namespaces
./shared/scripts/validate-marketplace.sh <product> --cleanup

# Build only (no validation) - from product directory
cd products/<product> && REGISTRY=gcr.io/$PROJECT_ID TAG=<version> make app/build

# Check image annotation
docker manifest inspect gcr.io/$PROJECT_ID/<product>:<tag> | grep service.name

# Validate Boundary (VM Solution)
cd products/boundary && cft blueprint metadata -p . -v
```

## Debugging

### Kubernetes Apps
```bash
# Check pod status
kubectl get pods -n <namespace>

# Check logs
kubectl logs -n <namespace> <pod> -c <container>

# Check Application CRD status
kubectl get applications -n <namespace>

# Health check (TFE)
curl -k https://<lb-ip>/_health_check

# Clean up test namespaces
kubectl delete ns apptest-*
```

### Boundary (VM Solution)
```bash
# SSH to controller via IAP
gcloud compute ssh boundary-controller-0 --tunnel-through-iap

# Check service status
sudo systemctl status boundary

# View logs
sudo journalctl -u boundary -f

# Check config
sudo cat /etc/boundary.d/boundary.hcl

# Connect to Cloud SQL
psql "postgresql://boundary:PASSWORD@CLOUD_SQL_IP:5432/boundary?sslmode=require"
```

## Environment Variables

| Variable | Description | Used By |
|----------|-------------|---------|
| `REGISTRY` | Container registry (e.g., `gcr.io/my-project`) | All K8s products |
| `TAG` | Image version tag (e.g., `1.22.1`) | All K8s products |
| `PROJECT_ID` | GCP project ID | All products |
| `TFE_LICENSE` | TFE license (for registry auth) | terraform-enterprise |
| `GKE_CLUSTER` | GKE cluster name | validate-marketplace.sh |
| `GKE_ZONE` | GKE cluster zone | validate-marketplace.sh |

## Critical Implementation Notes

### Scope Discipline (MANDATORY)

**NEVER work outside the scope of the current GitHub Issue. NEVER.**

- Before writing ANY code, verify it is within the scope of the assigned GitHub Issue
- If the issue says "frontend only" - do NOT touch backend files
- If the issue says "add endpoint X" - do NOT add endpoints Y and Z
- If you think something else needs to be done, CREATE A NEW ISSUE for it - do not scope creep
- When in doubt, ASK before implementing
- Review the issue's "Files to Create/Modify" section - that is the ONLY scope
- Existing endpoints exist for a reason (e.g., API key authentication) - do NOT duplicate them

**Examples of scope violations:**
- Issue says "Update frontend to display X" → Adding new backend endpoints = VIOLATION
- Issue says "Fix bug in function Y" → Refactoring unrelated code = VIOLATION
- Issue says "Add button to UI" → Creating new API routes = VIOLATION

### Data Storage
- **NEVER** change to memory storage - PostgreSQL is the permanent solution
- Database storage is mandatory for all features
- All data tests done locally with local PostgreSQL instance

### User Communication Requirements
1. Always ask for approval before making changes
2. Fully test any new feature before claiming completion
3. Ask questions/confirm understanding before implementing
4. NEVER modify working code without explicit user request

### PR and Commit Format

**PR Title:** Use Conventional Commits format
```
type(scope): short description in imperative mood
```
- Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`
- Scope: optional, identifies the module/area affected
- Description: lowercase, no period, imperative mood ("add" not "added")

Examples:
- `feat(auth): add OAuth2 login flow`
- `fix(api): handle null response from external service`
- `refactor(storage): extract database connection pooling`

**PR Body:** Keep it scannable and actionable
```markdown
## Summary

[1-2 sentences: what this PR does and why]

## Changes

- [Concrete deliverable 1]
- [Concrete deliverable 2]
- [Concrete deliverable 3]

## Testing

\`\`\`bash
[Runnable test commands]
\`\`\`

Closes #[issue-number]
```

**What to avoid:**
- Checkboxes for completed work (you're opening the PR, it's done)
- "Type of Change" sections (the PR title already conveys this)
- Verbose descriptions of obvious changes

### Git Commit and PR Rules
- **NEVER add Claude/AI attribution to commits or PRs** - No "🤖 Generated with Claude Code", "Co-Authored-By: Claude", or similar text in commit messages, PR descriptions, or any generated content
- Use semantic commit messages (feat:, fix:, chore:, docs:, refactor:, test:)
- Keep commit messages concise but descriptive