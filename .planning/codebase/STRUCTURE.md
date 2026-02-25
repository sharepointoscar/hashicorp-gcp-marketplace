# Codebase Structure

**Analysis Date:** 2025-02-24

## Directory Layout

```
hashicorp-gcp-marketplace/
├── README.md                           # Main repo documentation
├── CLAUDE.md                           # Repo-wide guidance (architecture rules, env isolation, etc.)
├── LICENSE                             # MPL-2.0
│
├── .planning/
│   └── codebase/                       # Codebase mapping documents (this directory)
│
├── .github/
│   └── workflows/                      # CI/CD pipelines
│
├── docs/
│   ├── adding-products.md              # Guide for adding new products
│   └── plans/                          # Planning documents
│
├── shared/                             # Shared build infrastructure (included by all products)
│   ├── Makefile.common                 # Common Make definitions, colors, build flags
│   ├── Makefile.product                # Generic product build rules (included by each product)
│   └── scripts/
│       ├── lib/
│       │   └── common.sh               # Shell functions (docker_build_mp, load_product_config, etc.)
│       └── validate-marketplace.sh     # Main K8s product validation orchestrator
│
├── vendor/                             # Third-party dependencies (git submodules)
│
└── products/
    ├── consul/                         # Kubernetes App - Service Mesh & Discovery
    ├── vault/                          # Kubernetes App - Secrets Management
    ├── terraform-enterprise/           # Kubernetes App - Terraform Automation + External Infra
    ├── terraform-cloud-agent/          # Kubernetes App - TFC Remote Execution Agent
    ├── boundary/                       # VM Solution - Secure Remote Access (Terraform)
    └── nomad/                          # VM Solution - Workload Orchestration (Terraform)
```

## Directory Purposes

**`.planning/codebase/`:**
- Purpose: Codebase analysis documents consumed by GSD commands
- Contains: ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, STACK.md, INTEGRATIONS.md, CONCERNS.md
- Key files: This directory

**`shared/`:**
- Purpose: Shared build infrastructure and validation tools for all products
- Contains: Make rules, shell functions, Docker build helpers, marketplace validation orchestrator
- Key files:
  - `Makefile.common` - Platform flags (`linux/amd64`), Docker build flags (provenance/sbom disabled), color helpers
  - `Makefile.product` - Generic targets: `images/build`, `app/verify`, `app/install`, `release`, `tags/minor`, `app/build`
  - `scripts/lib/common.sh` - Functions: `docker_build_mp()`, `load_product_config()`, `check_prerequisites()`, `check_mpdev()`
  - `scripts/validate-marketplace.sh` - Orchestrates full K8s product validation: prerequisites → build → schema check → mpdev install/verify → cleanup

**`products/` (Kubernetes Apps):**

Product directories follow identical structure:

```
products/vault/
├── README.md                           # Product user documentation
├── CLAUDE.md                           # Product-specific development guidance
├── Makefile                            # Product-specific build rules (includes shared/Makefile.product)
├── product.yaml                        # Metadata: id, version, partnerId, solutionId, images list
├── schema.yaml                         # GCP Marketplace schema - user inputs, defaults, validation
│
├── deployer/
│   └── Dockerfile                      # GCP Marketplace deployer image (instantiates manifests)
│
├── apptest/
│   └── deployer/
│       ├── Dockerfile                  # Tester image (runs mpdev verify)
│       └── schema.yaml                 # Test defaults for mpdev verify (all properties populated)
│
├── manifest/
│   ├── application.yaml.template       # GCP Application CRD (with $VARIABLE substitution)
│   └── manifests.yaml.template         # Kubernetes resources: Secret, ConfigMap, Services, StatefulSet
│
├── images/                             # Application container images
│   ├── vault/Dockerfile
│   ├── vault-init/Dockerfile
│   └── ubbagent/Dockerfile
│
└── .build/                             # Local build artifacts (not committed)
    └── vault-init/                     # Marker files tracking build state
```

**`products/` (VM Solutions):**

Terraform-based deployments:

```
products/boundary/
├── README.md                           # Product user documentation
├── CLAUDE.md                           # Product-specific development guidance
├── Makefile                            # Build/validation targets (terraform, cft, packer, package)
│
├── main.tf                             # Root module - instantiates prerequisites, controller, worker
├── variables.tf                        # Input variables (project_id, region, fqdn, counts, configs)
├── outputs.tf                          # Output values (URLs, IPs, resource IDs)
├── versions.tf                         # Provider constraints (terraform >=1.5.0, google >=5.0.0)
│
├── metadata.yaml                       # CFT Blueprint metadata (version, inputs/outputs, roles, services)
├── metadata.display.yaml               # GCP Marketplace UI form configuration
│
├── modules/                            # Terraform child modules
│   ├── controller/                     # Deploys controller VMs, Cloud SQL, KMS, load balancers
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── templates/
│   │   │   └── boundary_custom_data.sh.tpl  # Cloud-init script (idempotent)
│   │   └── ...
│   ├── worker/                         # Deploys ingress/egress worker VMs
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── templates/
│   │   │   └── boundary_custom_data.sh.tpl  # Cloud-init script (idempotent)
│   │   └── ...
│   └── prerequisites/                  # Creates Cloud KMS keys, service accounts, Secret Manager entries
│
├── packer/                             # Packer configuration for pre-baked VM images
│   ├── Makefile                        # Targets: packer/build, packer/inspect
│   ├── boundary.pkr.hcl                # Packer template (base image, install steps)
│   └── scripts/
│       └── install-boundary.sh         # Binary installation script
│
├── test/                               # Test configurations
│   └── marketplace_test.tfvars         # Variables for test deployments
│
└── .build/                             # Build artifacts (not committed)
    ├── *.zip                           # Packaged Terraform for GCS upload
    └── packer/                         # Packer build artifacts, logs
```

## Key File Locations

**Entry Points:**

- `shared/scripts/validate-marketplace.sh` - Primary entry point for K8s product validation
  - **Triggers:** `REGISTRY=... TAG=... ./shared/scripts/validate-marketplace.sh <product> [options]`
  - **Responsibilities:** Orchestrates prerequisites check, image build, schema validation, mpdev install/verify, cleanup

- `products/*/Makefile` - Product build entry points
  - **Targets:** `make release` (full build + version tags), `make app/build` (images only), `make app/verify` (mpdev verify)
  - **Pattern:** Each product defines `APP_ID`, `MP_SERVICE_NAME`, `REGISTRY`, then includes `shared/Makefile.product`

- `products/boundary/main.tf`, `products/nomad/main.tf` - Terraform root modules
  - **Triggers:** `terraform init`, `terraform plan`, `terraform apply`
  - **Responsibilities:** Instantiates child modules, orchestrates infrastructure

**Configuration:**

- `shared/Makefile.common` - Docker build flags, color definitions
- `products/*/product.yaml` - Product metadata (id, version, images list) — K8s apps only
- `products/*/schema.yaml` - GCP Marketplace UI inputs — K8s apps only
- `products/*/metadata.yaml` - CFT Blueprint definition — VM solutions only
- `products/*/metadata.display.yaml` - UI form customization — VM solutions only
- `products/*/variables.tf` - Terraform input variables — VM solutions only

**Core Logic:**

- `shared/scripts/lib/common.sh` - Reusable shell functions used by all products
  - `docker_build_mp()` - Wraps docker buildx with marketplace compliance flags
  - `load_product_config()` - Parses product.yaml
  - `check_prerequisites()`, `check_mpdev()` - Verify required tools

- `products/vault/manifest/manifests.yaml.template` - Example K8s manifest with variable substitution
  - Template variables: `$name`, `$replicas`, `$VAULT_LICENSE`, etc.
  - Deployed by deployer image using envsubst

- `products/boundary/modules/controller/templates/boundary_custom_data.sh.tpl` - Example cloud-init script
  - Idempotent design: skips installation if binary already present
  - Fetches license from Secret Manager at boot

**Testing:**

- `products/vault/apptest/deployer/Dockerfile` - Tester image that runs mpdev verify
- `products/vault/apptest/deployer/schema.yaml` - Test schema with all properties populated
- `products/boundary/test/marketplace_test.tfvars` - Test variables for terraform plan/apply

**Utilities:**

- `products/*/Makefile` - Product-specific targets beyond shared rules
  - Example: `products/vault/Makefile` defines `images/build` in addition to inherited targets
  - Example: `products/boundary/Makefile` defines `terraform/validate`, `packer/build`, `package`, `upload`

## Naming Conventions

**Files:**

- `*.yaml` or `*.yml` - Kubernetes manifests, GCP Marketplace schemas, Terraform metadata
- `Dockerfile` - Container image definitions (always named `Dockerfile`, no suffix)
- `*.template` - Template files with variable substitution (e.g., `manifests.yaml.template`)
- `*.tf` - Terraform configuration files
- `*.hcl` - HashiCorp configuration (e.g., `boundary.hcl` daemon config, `boundary.pkr.hcl` Packer)
- `*.tpl` - Template files in Terraform modules (e.g., cloud-init scripts)
- `Makefile` - Build orchestration (always named `Makefile`, product root or in subdirectories)
- `CLAUDE.md` - Product/repo-specific guidance for Claude Code
- `.build/` - Local build artifacts directory (git-ignored)
- `.gitignore` - Excludes build artifacts, state files, licenses, credentials

**Directories:**

- `products/<product-name>/` - One directory per product (e.g., `products/vault/`, `products/boundary/`)
  - Naming: lowercase, hyphen-separated (e.g., `terraform-enterprise`, `terraform-cloud-agent`)
- `products/<product>/deployer/` - Deployer image for K8s apps only
- `products/<product>/apptest/deployer/` - Tester image for K8s apps only
- `products/<product>/images/` - Container images for K8s apps (subdirectory per image: `vault/`, `vault-init/`, `ubbagent/`)
- `products/<product>/manifest/` - Kubernetes resource templates for K8s apps only
- `products/<product>/modules/` - Terraform child modules for VM solutions only
- `products/<product>/packer/` - Packer templates for VM image builds (VM solutions)
- `products/<product>/test/` - Test configurations and fixtures
- `shared/scripts/lib/` - Shared shell function libraries
- `shared/scripts/` - Executable scripts (no subdirectories except `lib/`)

**Environment Variables:**

- `REGISTRY` - Container registry (e.g., `us-docker.pkg.dev/project-id/product-marketplace`) — required for K8s builds
- `TAG` - Image version tag (e.g., `1.21.0`) — required for K8s builds
- `PROJECT_ID` - GCP project ID — used by all products
- `MP_SERVICE_NAME` - GCP Marketplace service annotation — required for K8s image annotations
- `GKE_CLUSTER`, `GKE_ZONE` - Cluster context for validation script

## Where to Add New Code

**New Kubernetes Product:**

1. Create directory: `products/<product-name>/`
2. Create product structure (Makefile, schema.yaml, product.yaml, deployer/, images/, manifest/, apptest/)
3. Add `product-name` to validation script line 43
4. Define `APP_ID` and `MP_SERVICE_NAME` in product Makefile
5. Place enterprise license as `products/<product-name>/*.hclic`
6. Validate: `REGISTRY=... TAG=... ./shared/scripts/validate-marketplace.sh <product-name>`

**New VM Solution Product:**

1. Create directory: `products/<product-name>/`
2. Create Terraform files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
3. Create CFT metadata: `metadata.yaml`, `metadata.display.yaml`
4. Create modules: `modules/prerequisites/`, `modules/main/` (adapt from HVD examples)
5. Create Packer config: `packer/` with cloud-init scripts
6. Validate: `terraform init && terraform validate && cft blueprint metadata -p . -v`

**New Shared Build Tool:**

- Add shell functions to: `shared/scripts/lib/common.sh`
- Add Make rules to: `shared/Makefile.common` or `shared/Makefile.product`
- Document in: This STRUCTURE.md and relevant product CLAUDE.md files

**Utilities & Helpers:**

- Shared utilities: `shared/scripts/lib/common.sh`
- Product-specific helpers: `products/<product>/scripts/` (if needed)
- Test helpers: `products/<product>/test/` or `products/<product>/apptest/`

## Special Directories

**`.build/`:**
- Purpose: Local build artifacts (marker files, logs)
- Generated: Yes (by make rules, touched to track build state)
- Committed: No (git-ignored)
- Cleanup: `make clean` removes entire directory

**`vendor/`:**
- Purpose: Git submodules for external dependencies (not currently used actively)
- Generated: No
- Committed: Yes (submodule references only, not full contents)
- Content: Referenced in `.gitmodules`

**`.planning/codebase/`:**
- Purpose: GSD codebase mapping documents
- Generated: Yes (by `/gsd:map-codebase` agent)
- Committed: Yes
- Content: ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, STACK.md, INTEGRATIONS.md, CONCERNS.md

**`.terraform/`, `terraform.tfstate*`:**
- Purpose: Terraform state and provider cache
- Generated: Yes (by terraform init/apply)
- Committed: No (git-ignored for security)
- Location: `products/boundary/terraform/`, `products/nomad/terraform/`

**`products/<product>/.build/`:**
- Purpose: Per-product build artifacts (touch markers for make dependencies)
- Generated: Yes (make targets)
- Committed: No (git-ignored)
- Example content: `vault/`, `vault-init/`, `ubbagent/`, `deployer`, `tester` (empty marker files)

---

*Structure analysis: 2025-02-24*
