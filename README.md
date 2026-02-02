# HashiCorp Products for Google Cloud Marketplace

This monorepo contains Google Cloud Marketplace packages for HashiCorp products.

## Products

| Product | GCP Marketplace Type | Status | Description |
|---------|---------------------|--------|-------------|
| [Terraform Enterprise](products/terraform-enterprise/) | Kubernetes App (Click-to-Deploy) | Active | Terraform automation with external services (Cloud SQL, Redis, GCS) |
| [Vault](products/vault/) | Kubernetes App (Click-to-Deploy) | Active | Secrets management with Raft integrated storage |
| [Consul](products/consul/) | Kubernetes App (Click-to-Deploy) | Active | Service mesh and service discovery |
| [Terraform Cloud Agent](products/terraform-cloud-agent/) | Kubernetes App (Click-to-Deploy) | Active | Terraform Cloud remote execution agent |
| [Boundary](products/boundary/) | VM Solution (Terraform Blueprint) | Active | Secure remote access with Cloud SQL, KMS, and worker proxies |
| Nomad | TBD | Planned | Workload orchestration |

### Product Types

- **Kubernetes App (Click-to-Deploy)**: Deployed to GKE via mpdev. Uses `schema.yaml` for marketplace UI inputs and a deployer container image. Validated with `validate-marketplace.sh`.
- **VM Solution (Terraform Blueprint)**: Deployed to Compute Engine VMs via Terraform. Uses `metadata.yaml` + `metadata.display.yaml` for marketplace UI. Validated with `cft blueprint metadata`.

## Repository Structure

```
hashicorp-gcp-marketplace/
├── shared/                        # Shared build infrastructure
│   ├── Makefile.common            # Docker flags, print helpers
│   ├── Makefile.product           # Generic deployer/tester build rules
│   └── scripts/
│       ├── lib/common.sh          # Shell functions
│       └── validate-marketplace.sh # Standard K8s validation script
├── products/
│   ├── terraform-enterprise/      # TFE - Kubernetes App
│   ├── vault/                     # Vault - Kubernetes App
│   ├── consul/                    # Consul - Kubernetes App
│   ├── terraform-cloud-agent/     # TFC Agent - Kubernetes App
│   └── boundary/                  # Boundary - VM Solution (Terraform)
└── docs/                          # Documentation
```

## Prerequisites

```bash
# Install required tools
gcloud components install kubectl

# Authenticate with GCP
gcloud auth login
gcloud auth configure-docker

# Set project
export PROJECT_ID=your-project-id
gcloud config set project $PROJECT_ID

# Initialize submodules
make init
```

## Quick Start

### Build a Product

```bash
# Set required variables
export REGISTRY=gcr.io/$PROJECT_ID
export TAG=1.21.0

# Build Vault
make PRODUCT=vault REGISTRY=$REGISTRY TAG=$TAG build

# Build Consul
make PRODUCT=consul REGISTRY=$REGISTRY TAG=$TAG build
```

### Validate a Product (Standard Workflow)

**Always use the shared validation script** for all products:

```bash
# Full validation pipeline (builds, schema check, install, verify, vuln scan)
REGISTRY=$REGISTRY TAG=$TAG ./shared/scripts/validate-marketplace.sh <product>

# Example: Terraform Enterprise
REGISTRY=$REGISTRY TAG=1.22.1 ./shared/scripts/validate-marketplace.sh terraform-enterprise

# Keep deployment for debugging
REGISTRY=$REGISTRY TAG=$TAG ./shared/scripts/validate-marketplace.sh <product> --keep-deployment
```

The script runs the complete pipeline:
1. Prerequisites and mpdev doctor
2. Build all images
3. Schema verification
4. mpdev install + mpdev verify
5. Vulnerability scan check

### Build All Products

```bash
make REGISTRY=$REGISTRY TAG=$TAG build-all
```

## Adding a New Product

See [docs/adding-products.md](docs/adding-products.md) for instructions on adding a new product to this monorepo.

## CI/CD

This repository uses Cloud Build with path filters to build only changed products. See [cloudbuild.yaml](cloudbuild.yaml) for details.

### Release Tags

Each product uses independent release tags:

| Product | Tag Pattern | Example |
|---------|-------------|---------|
| Terraform Enterprise | `tfe-v*` | `tfe-v1.1.3` |
| Vault | `vault-v*` | `vault-v1.21.0` |
| Consul | `consul-v*` | `consul-v1.22.2` |
| Terraform Cloud Agent | `tfc-agent-v*` | `tfc-agent-v1.0.0` |
| Boundary | `boundary-v*` | `boundary-v0.21.0` |

## License

MPL-2.0
