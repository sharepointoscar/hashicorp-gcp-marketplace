# Technology Stack

**Analysis Date:** 2025-02-24

## Languages

**Primary:**
- Go - HashiCorp products (Boundary, Vault, Consul, Terraform Enterprise) compiled binaries
- Bash - Build and deployment scripts across shared infrastructure and products
- HCL2 (Terraform) - Infrastructure provisioning (Boundary, Nomad, Terraform Enterprise pre-infra)
- YAML - Kubernetes manifests, GCP Marketplace schemas, Helm charts
- Makefiles - Build orchestration across all products

**Secondary:**
- Shell scripting - Validation and deployment automation (`shared/scripts/`)
- Python - Kubernetes cluster management utilities and cloud-init processing

## Runtime

**Environment:**
- Kubernetes 1.25+ (GKE) - Click-to-Deploy products (Vault, Consul, TFE, Terraform Cloud Agent)
- Compute Engine VMs - Boundary (GCP VM Solution via Terraform)
- Docker containers - Application and deployment images

**Container Runtime:**
- Docker/containerd with buildx for multi-platform builds (linux/amd64 only)

## Frameworks

**Core:**
- HashiCorp products - Vault Enterprise, Consul Enterprise, Terraform Enterprise, Boundary Enterprise
- Kubernetes via GCP Marketplace Click-to-Deploy (mpdev model)
- Terraform - Infrastructure as Code for Boundary (HVD modules) and pre-infrastructure

**Package Manager:**
- Helm - Chart-based deployment for Kubernetes products (TFE uses `chart/terraform-enterprise/`)
- Docker - Container image management

**Build/Dev:**
- Make - Build automation (shared `Makefile.common` + product-specific Makefiles)
- Packer - VM image builds (Boundary pre-baked Ubuntu 22.04 images)
- GCP Cloud Build - CI/CD pipeline for Marketplace validation
- Google Cloud Marketplace tools - deployer_helm, deployment validation

## Key Dependencies

**Critical:**

- **hashicorp/google** (Terraform) ~5.32 - GCP infrastructure provider (used in Boundary, TFE pre-infra)
- **hashicorp/google-beta** ~5.32 - GCP beta features (Cloud SQL, KMS, Cloud DNS)
- **hashicorp/random** ~3.0 - Random resource naming (IDs, suffixes)
- **hashicorp/tls** ~4.0 - TLS certificate generation (Boundary)
- **hashicorp/cloudinit** ~2.3 - Cloud-init configuration for VMs (Boundary)
- **Docker** - Container image building and pushing (all products)
- **kubectl** - Kubernetes cluster management (all K8s products)
- **mpdev** - GCP Marketplace deployer for Click-to-Deploy validation
- **cft** (Cloud Foundation Toolkit) - CFT Blueprint validation (Boundary VM solution)
- **Helm** - Kubernetes package manager for Helm-based deployments

**Infrastructure:**

- **google/c2d-debian11** - Base image for deployer containers (TFE)
- **gcr.io/cloud-marketplace-tools/k8s/deployer_helm** - GCP Marketplace deployer base
- **marketplace.gcr.io/google/*** - GCP Marketplace standard images

**Products (downloaded at runtime):**

- **hashicorp/vault-enterprise:X.X-ent** (Docker Hub) - Vault main image
- **hashicorp/vault-enterprise:X.X-ent-ubi** (Docker Hub) - Vault UBI variant (CVE workarounds)
- **hashicorp/consul-enterprise:X.X.X-ent** (DockerHub via `images.releases.hashicorp.com`) - Consul main image
- **hashicorp/terraform-enterprise:X.X.X** (private registry `images.releases.hashicorp.com`) - TFE main image
- **google.com/ubb-agent:latest** (Google registry) - UBB metering agent

## Configuration

**Environment:**

- **Test environment:** GCP project `ibm-software-mp-project-test`, GKE cluster `vault-mp-test` (us-central1-a)
- **Production environment:** GCP project `ibm-software-mp-project`, GKE cluster `vault-mp` (us-central1-a)
- Configuration loaded from:
  - `Makefile` variables (per-product: APP_ID, VERSION, REGISTRY, MP_SERVICE_NAME)
  - Environment variables (REGISTRY, TAG, PROJECT_ID, TFE_LICENSE)
  - `schema.yaml` - GCP Marketplace UI input definitions
  - `product.yaml` - Product metadata (id, version, partnerId, solutionId)
  - Terraform variables (`.tfvars` files)

**Build:**

- Docker build flags (Marketplace-compliant): `--platform=linux/amd64 --provenance=false --sbom=false --no-cache --pull`
- Image annotations: `com.googleapis.cloudmarketplace.product.service.name=<MP_SERVICE_NAME>` (REQUIRED)
- Image registry: Google Artifact Registry (`us-docker.pkg.dev/$PROJECT_ID/`)
- Version tagging strategy: Full semver (e.g., 1.1.3) + minor alias (e.g., 1.1) + major alias (e.g., 1)

**Secrets (Never committed):**

- `.env` - Environment variables (gitignored)
- `*.hclic` - Enterprise license files (gitignored, placed by user at product root)
- `.terraform/` - Terraform state directory (gitignored)
- `terraform.tfstate*` - Terraform state files (gitignored)

## Platform Requirements

**Development:**

- Docker (with buildx support for multi-stage builds)
- gcloud CLI (authenticated, configured for Artifact Registry)
- kubectl (configured to target test GKE cluster)
- Terraform 1.3+ (for infrastructure provisioning)
- Helm 3+ (for chart management)
- Make (build automation)
- mpdev CLI (GCP Marketplace deployer validation)
- cft CLI (CFT Blueprint validation - Boundary only)
- Packer (for Boundary VM image builds)

**Production:**

- GCP Cloud Marketplace - Listing and deployment portal
- GKE 1.33+ (Google's verification uses 1.33 and 1.35)
- Artifact Registry - Image hosting
- Cloud SQL (PostgreSQL 13+) - TFE/Boundary data persistence
- Memorystore Redis (optional) - TFE caching
- GCS - TFE/Boundary object storage
- Cloud KMS - Boundary encryption keys
- Secret Manager - License and credential storage
- Compute Engine - Boundary VM deployment
- Cloud Load Balancer - Service exposure

---

*Stack analysis: 2025-02-24*
