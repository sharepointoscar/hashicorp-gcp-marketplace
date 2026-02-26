# Architecture

**Analysis Date:** 2025-02-24

## Pattern Overview

**Overall:** Multi-product monorepo with two distinct deployment patterns: Kubernetes Click-to-Deploy (AppGate) and Terraform VM Solutions (Infrastructure-as-Code).

**Key Characteristics:**
- Shared build infrastructure (`shared/Makefile.common`, `shared/Makefile.product`) for all products
- Product-agnostic validation script (`shared/scripts/validate-marketplace.sh`) orchestrates testing across all Kubernetes apps
- Two primary architecture types: **K8s App** (container-based) and **VM Solution** (Terraform-based)
- GCP Marketplace compliance enforced at build time via Docker annotations and CFT metadata validation
- License and credential handling varies by product type

## Layers

**Build & Shared Infrastructure:**
- Purpose: Provide common tooling, build rules, and validation pipelines for all products
- Location: `shared/`
- Contains: Makefiles, shell functions, validation orchestrator
- Depends on: Docker, gcloud CLI, kubectl, mpdev (for K8s products), Terraform (for VM products)
- Used by: All products in `products/`

**Kubernetes Apps (Click-to-Deploy Products):**
- Purpose: GCP Marketplace Click-to-Deploy applications deployed to GKE via Google's mpdev tool
- Location: `products/vault/`, `products/consul/`, `products/terraform-enterprise/`, `products/terraform-cloud-agent/`
- Contains: Dockerfiles (app/deployer/tester), Kubernetes manifests, schema.yaml, product.yaml
- Depends on: Docker, GKE, mpdev, GCP Marketplace tooling
- Used by: GCP Marketplace Kubernetes App listings

**VM Solutions (Terraform Blueprint Products):**
- Purpose: Terraform-managed infrastructure deployments to Compute Engine VMs
- Location: `products/boundary/`, `products/nomad/`
- Contains: Terraform modules, metadata.yaml (CFT Blueprint), Packer images, cloud-init scripts
- Depends on: Terraform >=1.5.0, GCP Compute, Cloud SQL, Cloud KMS, GCS
- Used by: GCP Marketplace VM Solution listings

**Documentation & Examples:**
- Purpose: User guides, architecture diagrams, test configurations
- Location: `docs/`, `products/*/README.md`, `products/*/CLAUDE.md`
- Contains: Adding products, troubleshooting, product-specific guidance
- Depends on: Repository context
- Used by: Developers, operators

## Data Flow

**Kubernetes App Validation Flow:**

1. **Prerequisite Check** (`validate-marketplace.sh` line 60+)
   - Verifies docker, gcloud, kubectl, mpdev installed
   - Confirms project context and cluster access
   - Loads product configuration from `product.yaml`

2. **Image Build** (product Makefile)
   - App images: `images/*/Dockerfile` → pushed to REGISTRY with MP_SERVICE_NAME annotation
   - Deployer image: `deployer/Dockerfile` → packaged with manifests and schema
   - Tester image: `apptest/deployer/Dockerfile` → runs mpdev verify
   - All images tagged with semver: `TAG`, `MINOR_VERSION`, `MAJOR_VERSION`

3. **Schema Verification**
   - `validate-marketplace.sh` validates `schema.yaml` structure
   - Confirms `publishedVersion` matches across all metadata files

4. **Deployment Installation** (mpdev install)
   - Google's mpdev tool pulls deployer image
   - Deployer instantiates manifest templates with user inputs from schema
   - Creates namespace, secrets, configmaps, services, statefulsets

5. **Functionality Testing** (mpdev verify)
   - Tester pod runs verification suite
   - Validates application health, connectivity, and core functions
   - Exit code 0 = success, else = failure

6. **Cleanup**
   - Removes test namespaces, orphaned PVs, and (optionally) registry images
   - Restores cluster to clean state

**VM Solution Deployment Flow:**

1. **Terraform Initialization**
   - `terraform init` downloads provider plugins and modules
   - Loads modules from `modules/controller/`, `modules/worker/`, `modules/prerequisites/`

2. **Variable Provisioning**
   - User provides input via GCP Marketplace UI → captures in `metadata.display.yaml`
   - Terraform receives as `.tfvars`
   - Root module distributes to child modules

3. **Infrastructure Creation**
   - **Prerequisites Module**: Creates Cloud KMS keys, Secret Manager entries, IAM service accounts
   - **Controller Module**: Deploys controller VMs (MIG), Cloud SQL PostgreSQL, load balancers, firewall rules, Secrets Manager integration
   - **Worker Module**: Deploys ingress/egress worker VMs with optional load balancers, connects to controllers via KMS-encrypted credentials

4. **Cloud-Init Execution**
   - Pre-baked VM image includes Boundary/Nomad binary
   - Cloud-init script (from template) configures daemon, fetches license from Secret Manager, joins cluster
   - Script is idempotent — skips steps if already completed (handles pre-baked image behavior)

5. **Health Verification**
   - Controller health check: `curl -k https://<FQDN>:9200/health`
   - Worker registration: `journalctl -u boundary | grep "successfully"`
   - Terraform outputs provide access URLs and resource IDs

**State Management:**

- **Kubernetes Apps**: State stored in Kubernetes resources (StatefulSet, PVC, Secrets, ConfigMaps). Implicit with GKE cluster lifecycle.
- **VM Solutions**: State in Terraform tfstate files (`terraform.tfstate`, `terraform.tfstate.backup`). Must be protected and backed up. GCP Marketplace deployment metadata stored via `goog_cm_deployment_name` variable.
- **Registry Images**: Stored in Artifact Registry or GCR. Tagged with semver for version tracking.
- **Licenses**: Stored in Secret Manager (VM Solutions) or schema property (K8s Apps), never committed to git.

## Key Abstractions

**Shared Make Rules:**

- Purpose: Provide common build targets (`images/build`, `app/verify`, `app/install`, `release`, `tags/minor`, `ns/clean`)
- Examples: All products inherit from `shared/Makefile.product` pattern
- Pattern: Product Makefile defines `APP_ID`, `MP_SERVICE_NAME`, `REGISTRY`, product-specific rules then `include ../shared/Makefile.product`

**Deployer & Tester Pattern:**

- Purpose: Encapsulate GCP Marketplace integration (deployer) and validation (tester) in separate images
- Examples:
  - Deployer: `products/vault/deployer/Dockerfile` → reads manifests, substitutes user inputs into templates
  - Tester: `products/vault/apptest/deployer/Dockerfile` → runs health checks and functional tests
- Pattern: Deployer applies manifests, tester verifies via API calls or pod exec

**Manifest Templates:**

- Purpose: Define Kubernetes resources with variable substitution from GCP Marketplace UI inputs
- Examples:
  - `products/vault/manifest/application.yaml.template` - GCP Application CRD
  - `products/vault/manifest/manifests.yaml.template` - Secrets, ConfigMaps, Services, StatefulSet
  - Variables: `$name`, `$replicas`, `$VAULT_LICENSE`, etc.
- Pattern: Deployer uses `envsubst` or similar to replace `$VARIABLE` with schema property values

**Terraform Modules (VM Solutions):**

- Purpose: Encapsulate infrastructure components (controllers, workers, prerequisites) with reusable configuration
- Examples:
  - `products/boundary/modules/controller/` - Manages 60+ GCP resources (VMs, DB, KMS, LB)
  - `products/boundary/modules/worker/` - Manages worker VMs with ingress/egress configs
- Pattern: Root module (`main.tf`) instantiates child modules, coordinates inputs/outputs
- Marketplace adaptations: Add `goog_cm_deployment_name` for UI deployments, ensure idempotent cloud-init

**Cloud-Init Scripts (VM Solutions):**

- Purpose: Configure VMs at boot time (daemon setup, licensing, cluster registration)
- Examples: `products/boundary/modules/controller/templates/boundary_custom_data.sh.tpl`
- Pattern: Rendered as base64-encoded metadata, executed by systemd, logged to `/var/log/boundary-cloud-init.log`
- Key requirement: **Idempotent** - skip installation if binary/package already present (pre-baked image behavior)

**Packer Images (VM Solutions):**

- Purpose: Pre-bake Boundary/Nomad binaries into VM images to avoid runtime internet downloads
- Examples: `products/boundary/packer/`, `products/nomad/packer/`
- Pattern: Packer builds image from base OS, installs binary and dependencies, outputs GCP image family
- Marketplace requirement: Faster customer deployment, no external internet egress needed at runtime

## Entry Points

**Kubernetes App Entry Point - validate-marketplace.sh:**

- Location: `shared/scripts/validate-marketplace.sh`
- Triggers: User runs `REGISTRY=... TAG=... ./shared/scripts/validate-marketplace.sh <product>`
- Responsibilities:
  1. Parse arguments (product name, flags like `--keep-deployment`, `--cleanup`, `--cluster`)
  2. Load product configuration from `product.yaml`
  3. Run prerequisites check (`check_prerequisites`, `check_mpdev`)
  4. Build all images if `--gcr-clean` flag → registry cleanup
  5. Run `make app/build` in product directory
  6. Run schema validation
  7. Run `mpdev install` then `mpdev verify`
  8. Optionally keep deployment for debugging
  9. On success, provide image hashes and manifest details

**Kubernetes App Build Entry Point - Makefile:**

- Location: `products/*/Makefile`
- Triggers: `make app/build`, `make release`, `make images/build`
- Responsibilities:
  - Inherit from `shared/Makefile.product`
  - Define product-specific variables: `APP_ID`, `MP_SERVICE_NAME`, `REGISTRY`
  - Build app images with `docker buildx build` including `MP_SERVICE_NAME` annotation
  - Build deployer and tester images
  - Tag images with major/minor versions (via `make tags/*` rules)

**VM Solution Entry Point - main.tf:**

- Location: `products/boundary/main.tf`, `products/nomad/main.tf`
- Triggers: `terraform init`, `terraform plan`, `terraform apply`
- Responsibilities:
  - Load input variables from `variables.tf`
  - Call `modules/prerequisites/`, `modules/controller/`, `modules/worker/`
  - Pass marketplace metadata and licensing info to modules
  - Output access URLs, resource IDs, post-deployment instructions
  - Provide `goog_cm_deployment_name` for GCP Marketplace tracking

**VM Solution Validation Entry Point - metadata.yaml:**

- Location: `products/boundary/metadata.yaml`, `products/nomad/metadata.yaml`
- Triggers: `cft blueprint metadata -p . -v`
- Responsibilities:
  - Define CFT Blueprint structure (version, inputs, outputs, provider requirements, roles, services)
  - Validate Terraform provider constraints and required IAM roles
  - Document submodules, examples, and interfaces

## Error Handling

**Strategy:** Fail-fast with descriptive errors. K8s apps use mpdev exit codes; VM solutions use Terraform error messages.

**Patterns:**

- **Build-time validation**: Check required env vars (`REGISTRY`, `TAG`, `MP_SERVICE_NAME`) before docker build
  - Example: `shared/Makefile.product` errors if `REGISTRY` not set (line 11)
  - If `MP_SERVICE_NAME` empty, annotation flag skipped (line 22-26) — images lack service annotation

- **Schema validation**: `validate-marketplace.sh` runs mpdev schema check before install
  - Errors if `publishedVersion` mismatch across files
  - Errors if schema properties invalid

- **Deployment validation**: mpdev install/verify return non-zero exit code on failure
  - Pod startup failures → ImagePullBackOff, CrashLoopBackOff (captured in pod events)
  - Tester pod exit code non-zero → validation failed (logs accessible via kubectl)

- **Terraform validation**: `terraform validate`, `terraform plan` catch syntax and logic errors
  - Provider version mismatches surfaced at `terraform init`
  - Variable validation rules enforced on apply
  - Module input validation catches type/required field errors

- **Runtime logs**: All products log to stdout/stderr (pod logs or systemd journal)
  - K8s apps: `kubectl logs -n <ns> <pod> -c <container>`
  - VM solutions: `sudo journalctl -u boundary -f` or `/var/log/boundary-cloud-init.log`

## Cross-Cutting Concerns

**Logging:**

- **K8s Apps**: Pods write to stdout (container logs). Captured by kubectl logs, forwarded to GKE logs by Google.
  - Example: Vault logs contain initialization, sealing, health checks
  - Deployer logs show manifest rendering, image pulls
  - Tester logs show verification test results

- **VM Solutions**: Systemd journalctl and cloud-init logs.
  - Example: `/var/log/boundary-cloud-init.log` shows startup steps, idempotency checks
  - `journalctl -u boundary -f` shows daemon lifecycle, worker registration

**Validation:**

- **K8s Apps**: mpdev verify suite runs tests defined in apptest schema and tester image
  - Validates pod health (Running status, ready probes pass)
  - Validates application endpoints (API calls, UI access)
  - Example: Vault tester runs health check API
  - Example: Consul tester checks gossip protocol and DNS

- **VM Solutions**: Terraform validation and manual health checks
  - `terraform validate` checks syntax
  - `cft blueprint metadata -p . -v` validates CFT structure
  - Manual: `curl -k https://<FQDN>:9200/health` for controllers
  - Manual: SSH via IAP and check systemd status

**Authentication:**

- **K8s Apps**: Implicit (GKE cluster access via kubectl config)
  - Deployer accesses GKE via service account or user credentials
  - Tester pod runs in cluster with RBAC permissions
  - License stored in Secret (schema property or file-based)

- **VM Solutions**: GCP project IAM and Secret Manager
  - Terraform requires `compute.admin`, `cloudsql.admin`, `cloudkms.admin` roles
  - VMs authenticate to Cloud KMS via service account (generated by modules)
  - License fetched from Secret Manager at boot time
  - Workers authenticate to controllers using KMS-encrypted credentials

---

*Architecture analysis: 2025-02-24*
