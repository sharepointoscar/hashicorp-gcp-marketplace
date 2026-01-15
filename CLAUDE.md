# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this monorepo.

## Repository Overview

This is a **GCP Marketplace monorepo** for HashiCorp products. Each product in `products/` is a self-contained GCP Marketplace deployer that can be independently built, validated, and published.

## Standard Validation Workflow

**Always use the shared validation script for ALL products:**

```bash
REGISTRY=gcr.io/$PROJECT_ID TAG=<version> \
  ./shared/scripts/validate-marketplace.sh <product-name>
```

This runs the complete pipeline:
1. Prerequisites check + mpdev doctor
2. Build all images (`make app/build`)
3. Schema verification
4. mpdev install (test deployment)
5. mpdev verify (full verification)
6. Vulnerability scan check

**Always provide image hashes** after running the workflow.

## Repository Structure

```
hashicorp-gcp-marketplace/
├── shared/                          # Shared build infrastructure
│   ├── Makefile.common              # Docker flags, print helpers
│   ├── Makefile.product             # Generic deployer/tester build rules
│   └── scripts/
│       └── validate-marketplace.sh  # Standard validation script
├── products/
│   ├── terraform-enterprise/        # TFE (External Services mode)
│   └── vault/                       # Vault (Integrated Storage)
```

## Product Architecture

Each product follows this structure:

```
products/<product>/
├── Makefile                         # Product-specific build targets
├── schema.yaml                      # GCP Marketplace schema (user inputs)
├── product.yaml                     # Product metadata (optional)
├── CLAUDE.md                        # Product-specific guidance
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

## Shared Makefiles

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

## Product Comparison

| Aspect | Terraform Enterprise | Vault | Consul | Nomad | Boundary |
|--------|---------------------|-------|--------|-------|----------|
| **Storage Mode** | External Services (Cloud SQL, Redis, GCS) | Integrated (Raft) | TBD | TBD | TBD |
| **Infrastructure** | Requires Terraform pre-provisioning | Self-contained | TBD | TBD | TBD |
| **Registry Auth** | Required (`images.releases.hashicorp.com`) | Not required | TBD | TBD | TBD |
| **UBB Agent** | Custom build (security patches) | Pulled from Google | TBD | TBD | TBD |
| **Complexity** | High (TLS, DB encoding, encryption) | Low (replicas, storage) | TBD | TBD | TBD |

## Product-Specific Workflows

### Terraform Enterprise

**Prerequisites:**
```bash
# Authenticate to HashiCorp registry
docker login images.releases.hashicorp.com -u terraform -p $TFE_LICENSE

# Pre-provision infrastructure (Cloud SQL, Redis, GCS, GKE)
cd products/terraform-enterprise/terraform && terraform apply
```

**Validation:**
```bash
REGISTRY=gcr.io/$PROJECT_ID TAG=1.22.1 \
  ./shared/scripts/validate-marketplace.sh terraform-enterprise
```

**Key considerations:**
- DATABASE_URL requires URL-encoded password (`/` → `%2F`)
- ENC_PASSWORD must match TFE_ENCRYPTION_PASSWORD
- Clean vault tables between mpdev verify runs (stale encryption data)
- See `products/terraform-enterprise/CLAUDE.md` for detailed troubleshooting

### Vault

**Prerequisites:**
```bash
# No special auth required - uses public images
gcloud auth configure-docker
```

**Validation:**
```bash
REGISTRY=gcr.io/$PROJECT_ID TAG=1.21.0 \
  ./shared/scripts/validate-marketplace.sh vault
```

**Key considerations:**
- Uses Raft integrated storage (no external DB)
- UBB agent pulled directly from Google's registry

## GCP Marketplace Verification Requirements

Apps are executed in Google's Verification system to ensure that:

1. **Installation succeeds**: All resources are applied and waited for to become healthy
2. **Functionality tests pass**: The deployer starts the Tester Pod and watches its exit status (zero = success, non-zero = failure)
3. **Uninstallation succeeds**: App and all its resources are successfully removed from the cluster

**Successful results are required before an app can be published to Google Cloud Marketplace.**

**Google's test clusters run GKE versions 1.33 and 1.35** - ensure compatibility with these versions.

## GCP Marketplace Image Requirements

All images must be:
- Single architecture: `linux/amd64`
- Docker V2 manifests: `--provenance=false --sbom=false`
- Annotated: `com.googleapis.cloudmarketplace.product.service.name=<MP_SERVICE_NAME>`
- Tagged with semver: `1.22.1` (full) and `1.22` (minor alias)

## Version Synchronization

For each product, these files must have matching versions:
1. `schema.yaml` → `publishedVersion`
2. `apptest/deployer/schema.yaml` → `publishedVersion`
3. `manifest/application.yaml.template` → `version`

## Adding a New Product

1. Create directory: `products/<product-name>/`
2. Copy structure from existing product (vault is simpler template)
3. Create product-specific Makefile defining `APP_ID` and `MP_SERVICE_NAME`
4. Create schema.yaml with user inputs
5. Create manifest templates
6. Create Dockerfiles for app images
7. Create CLAUDE.md with product-specific guidance
8. Validate: `./shared/scripts/validate-marketplace.sh <product-name>`

## Common Commands

```bash
# Validate any product (STANDARD WORKFLOW)
REGISTRY=gcr.io/$PROJECT_ID TAG=<version> \
  ./shared/scripts/validate-marketplace.sh <product>

# Build only (no validation)
cd products/<product> && REGISTRY=gcr.io/$PROJECT_ID TAG=<version> make app/build

# Clean GCR images
cd products/<product> && REGISTRY=gcr.io/$PROJECT_ID make gcr/clean

# Check image annotation
docker manifest inspect gcr.io/$PROJECT_ID/<product>:<tag> | grep service.name
```

## Debugging

```bash
# Check pod status
kubectl get pods -n <namespace>

# Check logs
kubectl logs -n <namespace> <pod> -c <container>

# Health check
curl -k https://<lb-ip>/_health_check

# Clean up test namespaces
kubectl delete ns apptest-*
```
