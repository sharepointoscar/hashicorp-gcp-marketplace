# HashiCorp Products for Google Cloud Marketplace

This monorepo contains Google Cloud Marketplace packages for HashiCorp products.

## Products

| Product | Status | Description |
|---------|--------|-------------|
| [Vault](products/vault/) | Active | Secrets management and data protection |
| [Consul](products/consul/) | Planned | Service mesh and service discovery |
| [Nomad](products/nomad/) | Planned | Workload orchestration |
| [Terraform](products/terraform/) | Planned | Terraform Cloud Agent |

## Repository Structure

```
hashicorp-gcp-marketplace/
├── Makefile                    # Root orchestration
├── shared/                     # Shared infrastructure
│   ├── Makefile.common         # Common make targets
│   ├── Makefile.product        # Product build patterns
│   ├── scripts/                # Validation and cluster scripts
│   └── templates/              # Shared templates
├── products/                   # Product-specific code
│   ├── vault/
│   ├── consul/
│   ├── nomad/
│   └── terraform/
├── vendor/
│   └── marketplace-tools/      # Google's marketplace toolkit
└── docs/                       # Documentation
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

### Validate a Product

```bash
# Run full validation for Vault
make PRODUCT=vault REGISTRY=$REGISTRY TAG=$TAG validate

# Or use the script directly
./shared/scripts/validate-marketplace.sh vault
```

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
| Vault | `vault-v*` | `vault-v1.21.0` |
| Consul | `consul-v*` | `consul-v1.18.0` |
| Nomad | `nomad-v*` | `nomad-v1.7.0` |
| Terraform | `terraform-v*` | `terraform-v1.0.0` |

## License

MPL-2.0
