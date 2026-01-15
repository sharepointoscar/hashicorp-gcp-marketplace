# HashiCorp Products for Google Cloud Marketplace

This monorepo contains Google Cloud Marketplace packages for HashiCorp products.

## Products

| Product | Type | Status | Description |
|---------|------|--------|-------------|
| [TFE (Terraform K8s App)](products/terraform-enterprise-tf/) | Terraform K8s App | Active | Full-stack deployment with Infrastructure Manager |
| [TFE (Click-to-Deploy)](products/terraform-enterprise/) | Click-to-Deploy | Active | Requires pre-provisioned infrastructure |
| [Vault](products/vault/) | Click-to-Deploy | Active | Secrets management with Raft storage |
| [Consul](products/consul/) | Click-to-Deploy | Planned | Service mesh and service discovery |
| [Nomad](products/nomad/) | Click-to-Deploy | Planned | Workload orchestration |
| [Terraform Cloud Agent](products/terraform/) | Click-to-Deploy | Planned | Terraform Cloud Agent |

### Deployment Types

- **Terraform K8s App**: Uses GCP Infrastructure Manager to provision ALL infrastructure (VPC, GKE, Cloud SQL, Redis, GCS) and deploy via Helm. Best for marketplace since it's self-contained.
- **Click-to-Deploy**: Requires pre-provisioned infrastructure. Customer must set up Cloud SQL, Redis, etc. before deployment.

## Repository Structure

```
hashicorp-gcp-marketplace/
├── Makefile                       # Root orchestration
├── shared/                        # Shared infrastructure
│   ├── Makefile.common            # Common make targets
│   ├── Makefile.product           # Product build patterns
│   ├── scripts/                   # Validation and cluster scripts
│   └── templates/                 # Shared templates
├── products/                      # Product-specific code
│   ├── terraform-enterprise-tf/   # TFE Terraform K8s App (Active)
│   ├── terraform-enterprise/      # TFE Click-to-Deploy (Active)
│   ├── vault/
│   ├── consul/
│   ├── nomad/
│   └── terraform/
├── vendor/
│   └── marketplace-tools/         # Google's marketplace toolkit
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
| TFE Terraform K8s App | `tfe-tf-v*` | `tfe-tf-v1.0.0` |
| TFE Click-to-Deploy | `tfe-v*` | `tfe-v1.0.2` |
| Vault | `vault-v*` | `vault-v1.21.0` |
| Consul | `consul-v*` | `consul-v1.18.0` |
| Nomad | `nomad-v*` | `nomad-v1.7.0` |
| Terraform Cloud Agent | `terraform-v*` | `terraform-v1.0.0` |

## License

MPL-2.0
