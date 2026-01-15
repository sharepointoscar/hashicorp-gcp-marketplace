# TFE GCP Marketplace - Terraform Kubernetes App Migration

## Problem Statement

Current click-to-deploy model (envsubst deployer + raw K8s manifests) with in-cluster dependencies (PostgreSQL, Redis, MinIO) has database migration issues. Converting to Terraform K8s App model per [GCP Packaging Guide](https://github.com/GoogleCloudPlatform/marketplace-tools/tree/master/docs/terraform-k8s-app).

---

## Solution Overview

Use **Terraform K8s App model** with:
- Terraform module using Helm provider
- HashiCorp's official [terraform-enterprise-helm](https://github.com/hashicorp/terraform-enterprise-helm) chart (pushed to AR)
- External managed services: Cloud SQL, Memorystore, GCS
- Validation via `terraform plan` (NOT mpdev)

### How Infrastructure Gets Provisioned

The **Terraform module** provisions ALL infrastructure when deployed:

```
Customer Deploys via GCP Marketplace
                │
                ▼
    Infrastructure Manager (runs terraform apply)
                │
    ┌───────────┴───────────────────────┐
    │                                   │
    ▼                                   ▼
modules/infrastructure/              helm.tf
├── cloudsql.tf → Cloud SQL         helm_release "tfe"
├── redis.tf    → Memorystore         ├── database_host (from infra)
├── gcs.tf      → GCS Bucket          ├── redis_host (from infra)
└── iam.tf      → Service Accounts    └── gcs_bucket (from infra)
```

**Key Point**: The Terraform module we package includes BOTH:
1. Infrastructure resources (Cloud SQL, Redis, GCS) in `modules/infrastructure/`
2. Helm release in `helm.tf` that uses infrastructure outputs

---

## Phase 0: Cleanup

### Delete from GCR
```bash
# Clean all TFE images from gcr.io
cd products/terraform-enterprise
REGISTRY=gcr.io/ibm-software-mp-project-test make gcr/clean
```

### Delete Unused Files
```
products/terraform-enterprise/
├── manifest/                    # DELETE - raw K8s manifests
├── deployer/                    # DELETE - envsubst deployer
├── apptest/                     # DELETE - mpdev tester
├── images/postgresql/           # DELETE - in-cluster DB
├── images/redis/                # DELETE - in-cluster Redis
├── images/minio/                # DELETE - in-cluster S3
├── images/tester/               # DELETE - mpdev tester image
└── schema.yaml                  # DELETE - click-to-deploy schema
```

### Keep/Reuse
```
products/terraform-enterprise/
├── images/tfe/Dockerfile        # KEEP - TFE container image
├── images/ubbagent/Dockerfile   # KEEP - UBB billing agent
├── terraform/                   # ADAPT - infrastructure code
├── Makefile                     # REWRITE - new targets
└── CLAUDE.md                    # UPDATE - new guidance
```

---

## Target Directory Structure

Based on [GCP starter-terraform-module](https://github.com/GoogleCloudPlatform/marketplace-tools/tree/master/docs/terraform-k8s-app/starter-terraform-module):

```
products/terraform-enterprise/
├── main.tf                      # Providers, API enablement, random suffix
├── gke.tf                       # GKE cluster data source (EXISTING ONLY)
├── helm.tf                      # helm_release for TFE
├── variables.tf                 # All input variables
├── outputs.tf                   # LB IP, URLs, endpoints
├── versions.tf                  # Provider requirements
├── schema.yaml                  # Image URI mapping (NEW format)
├── marketplace_test.tfvars      # Test values for validation
├── Makefile                     # Build, package, validate targets
├── CLAUDE.md                    # Updated guidance
├── helm/                        # NEW - Helm chart (must be in AR)
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── templates/
│   │   ├── _helpers.tpl
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── secrets.yaml
│   │   └── ubbagent-sidecar.yaml
│   └── .helmignore
├── images/
│   ├── tfe/Dockerfile           # TFE image (reuse)
│   └── ubbagent/Dockerfile      # UBB agent (reuse)
└── modules/
    └── infrastructure/          # Cloud SQL, Redis, GCS
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

**Note**: GKE cluster is EXISTING ONLY - no cluster creation. Customer must have a pre-existing GKE cluster.

---

## Key Files

### 1. versions.tf
```hcl
terraform {
  required_version = ">= 1.9"
  required_providers {
    google      = { source = "hashicorp/google", version = "~> 5.42" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 5.42" }
    helm        = { source = "hashicorp/helm", version = "~> 2.12" }
    kubernetes  = { source = "hashicorp/kubernetes", version = "~> 2.25" }
    random      = { source = "hashicorp/random", version = "~> 3.6" }
  }
}
```

### 2. main.tf
```hcl
provider "google" {
  project = var.project_id
}

provider "google-beta" {
  project = var.project_id
}

data "google_client_config" "default" {}
data "google_project" "project" {}

# Enable required APIs
module "project_services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 17.0"

  project_id = var.project_id
  activate_apis = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "redis.googleapis.com",
    "storage.googleapis.com",
    "servicenetworking.googleapis.com",
    "iam.googleapis.com",
  ]
}

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}
```

### 3. helm.tf (Key File)
```hcl
provider "helm" {
  alias = "tfe"
  kubernetes {
    host                   = "https://${data.google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }
}

locals {
  helm_release_name = coalesce(var.helm_release_name, "tfe-${random_string.suffix.result}")
}

resource "helm_release" "tfe" {
  provider   = helm.tfe
  name       = local.helm_release_name
  namespace  = var.namespace
  repository = var.helm_chart_repo
  chart      = var.helm_chart_name
  version    = var.helm_chart_version

  # TFE Configuration
  set {
    name  = "replicaCount"
    value = jsonencode(var.replica_count)
  }

  set {
    name  = "tfe.hostname"
    value = var.tfe_hostname
  }

  # Database (from infrastructure module)
  set {
    name  = "env.variables.TFE_DATABASE_HOST"
    value = "${module.infrastructure.database_host}:5432"
  }

  set_sensitive {
    name  = "env.secrets.TFE_DATABASE_PASSWORD"
    value = module.infrastructure.database_password
  }

  # Redis (from infrastructure module)
  set {
    name  = "env.variables.TFE_REDIS_HOST"
    value = module.infrastructure.redis_host
  }

  # GCS (from infrastructure module)
  set {
    name  = "env.variables.TFE_OBJECT_STORAGE_GOOGLE_BUCKET"
    value = module.infrastructure.gcs_bucket
  }

  # License & Encryption
  set_sensitive {
    name  = "env.secrets.TFE_LICENSE"
    value = var.tfe_license
  }

  # Image configuration (for marketplace image replacement)
  set {
    name  = "image.repository"
    value = jsonencode(var.tfe_image_repo)
  }

  set {
    name  = "image.tag"
    value = jsonencode(var.tfe_image_tag)
  }
}
```

### 4. schema.yaml (NEW FORMAT - Image URI Mapping)

**CRITICAL**: This is NOT the click-to-deploy schema. This maps Terraform variables to image URIs:

```yaml
# schema.yaml - Maps Terraform variables to Docker image URI components
# Reference: https://github.com/GoogleCloudPlatform/marketplace-tools/blob/master/docs/terraform-k8s-app/terraform-k8s-app-packaging-guide.md

images:
  tfe:
    variables:
      tfe_image_repo:
        type: REPO_WITH_REGISTRY_WITH_NAME
      tfe_image_tag:
        type: TAG
  ubbagent:
    variables:
      ubbagent_image_repo:
        type: REPO_WITH_REGISTRY_WITH_NAME
      ubbagent_image_tag:
        type: TAG
```

### 5. gke.tf (Existing Cluster Only)
```hcl
# GKE cluster data source - assumes existing cluster
data "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.cluster_location
  project  = var.project_id
}

# Kubernetes provider using existing cluster credentials
provider "kubernetes" {
  alias                  = "app"
  host                   = "https://${data.google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}
```

### 6. marketplace_test.tfvars

```hcl
# Test values for GCP Marketplace validation
# DO NOT include: project_id, helm_chart_repo, helm_chart_name, helm_chart_version
# DO NOT include: variables declared in schema.yaml (tfe_image_repo, tfe_image_tag, etc.)

cluster_name     = "vault-mp-test"  # Use existing test cluster
cluster_location = "us-central1"
namespace        = "terraform-enterprise"
tfe_hostname     = "tfe.example.com"
replica_count    = 1
```

---

## Helm Chart (CRITICAL - Must be in Artifact Registry)

**Per GCP Producer Portal**: The Helm chart MUST be stored in Artifact Registry (AR), NOT from external sources like `helm.releases.hashicorp.com`.

### Helm Chart URL Format
```
us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace/terraform-enterprise-chart
```

### Approach: Fork HashiCorp's Helm Chart

1. Clone https://github.com/hashicorp/terraform-enterprise-helm
2. Adapt for GCP Marketplace (add UBB sidecar, marketplace annotations)
3. Package and push to Artifact Registry

### Directory Structure for Helm Chart
```
products/terraform-enterprise/
├── helm/                        # NEW - Helm chart directory
│   ├── Chart.yaml               # Chart metadata (version must match images)
│   ├── values.yaml              # Default values
│   ├── templates/
│   │   ├── _helpers.tpl
│   │   ├── deployment.yaml      # TFE deployment (adapted from HashiCorp)
│   │   ├── service.yaml
│   │   ├── secrets.yaml
│   │   ├── configmap.yaml
│   │   └── ubbagent-sidecar.yaml  # UBB agent for billing
│   └── .helmignore
```

### Chart.yaml Example
```yaml
apiVersion: v2
name: terraform-enterprise-chart
description: HashiCorp Terraform Enterprise for GCP Marketplace
type: application
version: 1.1.3        # Must match container image version
appVersion: "1.1.3"
```

### Push Helm Chart to Artifact Registry
```bash
# Package the chart
cd products/terraform-enterprise/helm
helm package . --version 1.1.3

# Push to Artifact Registry (OCI format)
helm push terraform-enterprise-chart-1.1.3.tgz \
  oci://us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace
```

### Helm Chart URL for Producer Portal
```
us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace/terraform-enterprise-chart
```

### In Terraform module (helm.tf)
```hcl
variable "helm_chart_repo" {
  type    = string
  default = "oci://us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace"
}

variable "helm_chart_name" {
  type    = string
  default = "terraform-enterprise-chart"
}

variable "helm_chart_version" {
  type    = string
  default = "1.1.3"
}
```

---

## Makefile (Rewritten)

```makefile
APP_ID := terraform-enterprise
VERSION := 1.1.3
CHART_NAME := terraform-enterprise-chart

# Artifact Registry (MUST be us-docker.pkg.dev for Terraform K8s apps)
AR_REGISTRY := us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace
MP_SERVICE_NAME := services/tfe-self-managed.endpoints.ibm-software-mp-project-test.cloud.goog

# Cloud Storage for Terraform module ZIP
TF_MODULE_BUCKET := gs://ibm-software-mp-project-test-tf-modules

include ../../shared/Makefile.common

#=============================================================================
# HELM CHART TARGETS (REQUIRED for Terraform K8s App)
#=============================================================================

.PHONY: helm/lint
helm/lint:
	$(call print_notice,Linting Helm chart...)
	helm lint helm/

.PHONY: helm/package
helm/package: helm/lint
	$(call print_notice,Packaging Helm chart...)
	@mkdir -p .build
	helm package helm/ --version $(VERSION) --destination .build/

.PHONY: helm/push
helm/push: helm/package
	$(call print_notice,Pushing Helm chart to Artifact Registry...)
	helm push .build/$(CHART_NAME)-$(VERSION).tgz oci://$(AR_REGISTRY)
	$(call print_success,Chart pushed: $(AR_REGISTRY)/$(CHART_NAME):$(VERSION))

#=============================================================================
# IMAGE TARGETS (TFE + UBB)
#=============================================================================

.PHONY: images/build
images/build: .build/tfe .build/ubbagent

.build/tfe: images/tfe/Dockerfile
	$(call print_notice,Building TFE image...)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		--annotation "com.googleapis.cloudmarketplace.product.service.name=$(MP_SERVICE_NAME)" \
		--tag "$(AR_REGISTRY)/tfe:$(VERSION)" \
		-f images/tfe/Dockerfile --push images/tfe
	@mkdir -p .build && touch $@

.build/ubbagent: images/ubbagent/Dockerfile
	$(call print_notice,Building UBB agent image...)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		--annotation "com.googleapis.cloudmarketplace.product.service.name=$(MP_SERVICE_NAME)" \
		--tag "$(AR_REGISTRY)/ubbagent:$(VERSION)" \
		-f images/ubbagent/Dockerfile --push images/ubbagent
	@mkdir -p .build && touch $@

#=============================================================================
# TERRAFORM MODULE TARGETS
#=============================================================================

.PHONY: terraform/validate
terraform/validate:
	$(call print_notice,Validating Terraform module...)
	terraform init -backend=false
	terraform validate

.PHONY: terraform/plan
terraform/plan:
	$(call print_notice,Running terraform plan...)
	terraform init
	terraform plan -var-file=marketplace_test.tfvars

.PHONY: terraform/package
terraform/package:
	$(call print_notice,Packaging Terraform module ZIP...)
	@mkdir -p .build
	zip -r .build/$(APP_ID)-$(VERSION).zip \
		*.tf modules/ schema.yaml marketplace_test.tfvars \
		-x "*.terraform*" -x "*.tfstate*" -x ".build/*" -x "helm/*" -x "images/*"

.PHONY: terraform/upload
terraform/upload: terraform/package
	$(call print_notice,Uploading to Cloud Storage...)
	gsutil cp .build/$(APP_ID)-$(VERSION).zip \
		$(TF_MODULE_BUCKET)/$(APP_ID)/$(VERSION)/

#=============================================================================
# VALIDATION (replaces mpdev verify)
#=============================================================================

.PHONY: validate
validate: helm/lint terraform/validate terraform/plan
	$(call print_success,Validation complete!)

#=============================================================================
# FULL RELEASE PIPELINE
#=============================================================================

.PHONY: release
release: images/build helm/push terraform/upload
	$(call print_success,Release $(VERSION) complete!)
	@echo ""
	@echo "=== ARTIFACTS ==="
	@echo "Helm Chart URL: $(AR_REGISTRY)/$(CHART_NAME)"
	@echo "TFE Image:      $(AR_REGISTRY)/tfe:$(VERSION)"
	@echo "UBB Image:      $(AR_REGISTRY)/ubbagent:$(VERSION)"
	@echo "TF Module:      $(TF_MODULE_BUCKET)/$(APP_ID)/$(VERSION)/"
	@echo ""
	@echo "=== PRODUCER PORTAL ==="
	@echo "Helm Chart URL to enter: $(AR_REGISTRY)/$(CHART_NAME)"

#=============================================================================
# CLEANUP
#=============================================================================

.PHONY: clean
clean:
	rm -rf .build/ .terraform/ *.tfstate*

.PHONY: ar/clean
ar/clean:
	$(call print_notice,Cleaning Artifact Registry...)
	gcloud artifacts docker images delete $(AR_REGISTRY)/tfe:$(VERSION) --quiet || true
	gcloud artifacts docker images delete $(AR_REGISTRY)/ubbagent:$(VERSION) --quiet || true
	gcloud artifacts docker images delete $(AR_REGISTRY)/$(CHART_NAME):$(VERSION) --quiet || true
```

---

## Validation Workflow

**NOT using mpdev verify** - Terraform K8s apps use `terraform plan` per [GCP packaging guide](https://github.com/GoogleCloudPlatform/marketplace-tools/blob/master/docs/terraform-k8s-app/terraform-k8s-app-packaging-guide.md):

> "Marketplace will do a verification based on the Terraform modules you provide, and with a set of test variables"

```bash
# Step 1: Validate syntax
cd products/terraform-enterprise
terraform init -backend=false
terraform validate

# Step 2: Plan with test values (mimics Marketplace validation)
terraform plan -var-file=marketplace_test.tfvars

# Step 3: (Optional) Apply to existing test cluster
terraform apply -var-file=marketplace_test.tfvars -auto-approve

# Step 4: Health check
curl -k https://<LB_IP>/_health_check
```

**Shared Script Update**: The existing `shared/scripts/validate-marketplace.sh` will NOT be used for Terraform K8s apps. Validation is done via `make validate` which runs `terraform validate` and `terraform plan`.

---

## Implementation Steps

### Step 1: Clean up old images from GCR
```bash
cd products/terraform-enterprise
REGISTRY=gcr.io/ibm-software-mp-project-test make gcr/clean
```

### Step 2: Delete unused files
```bash
rm -rf manifest/ deployer/ apptest/
rm -rf images/postgresql/ images/redis/ images/minio/ images/tester/
rm schema.yaml product.yaml  # Old click-to-deploy files
rm -rf terraform/  # Old terraform directory (will recreate)
```

### Step 3: Create Artifact Registry repository
```bash
gcloud artifacts repositories create tfe-marketplace \
  --repository-format=docker \
  --location=us \
  --project=ibm-software-mp-project-test
```

### Step 4: Create Cloud Storage bucket for Terraform module
```bash
gsutil mb -l us-central1 gs://ibm-software-mp-project-test-tf-modules
gsutil versioning set on gs://ibm-software-mp-project-test-tf-modules
```

### Step 5: Clone and adapt HashiCorp Helm chart
```bash
# Clone the official chart
git clone https://github.com/hashicorp/terraform-enterprise-helm /tmp/tfe-helm

# Copy to helm/ directory
mkdir -p helm/
cp -r /tmp/tfe-helm/* helm/

# Adapt Chart.yaml with our naming and version
# Add UBB agent sidecar template
# Update values.yaml with marketplace defaults
```

### Step 6: Create Terraform module files
- versions.tf, main.tf, variables.tf, outputs.tf
- gke.tf (existing cluster data source)
- helm.tf (helm_release using AR chart)
- modules/infrastructure/ (Cloud SQL, Redis, GCS)

### Step 7: Create schema.yaml (image URI mapping)
```yaml
images:
  tfe:
    variables:
      tfe_image_repo:
        type: REPO_WITH_REGISTRY_WITH_NAME
      tfe_image_tag:
        type: TAG
```

### Step 8: Create marketplace_test.tfvars
```hcl
cluster_name     = "vault-mp-test"
cluster_location = "us-central1"
namespace        = "terraform-enterprise"
tfe_hostname     = "tfe.example.com"
```

### Step 9: Update Makefile with new targets
- helm/lint, helm/package, helm/push
- images/build (TFE + UBB only)
- terraform/validate, terraform/package, terraform/upload
- release (full pipeline)

### Step 10: Build and push all artifacts
```bash
make release
```
This will:
1. Build and push TFE + UBB images to Artifact Registry
2. Package and push Helm chart to Artifact Registry
3. Package and upload Terraform module to Cloud Storage

### Step 11: Validate
```bash
make validate
```

### Step 12: Configure Deployment in Producer Portal

Per [GCP deployment configuration guide](https://docs.cloud.google.com/marketplace/docs/partners/terraform-kubernetes/configure-deployment):

1. Navigate to **Deployment configuration** tab
2. Enter **Helm Chart URL**:
   ```
   us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace/terraform-enterprise-chart
   ```
3. Click **Specify Releases** and configure:
   - **Display tag**: `1.1.3` (must match AR Helm chart tag)
   - **Version title**: `Terraform Enterprise 1.1.3`
   - **Description**: `Initial release with Cloud SQL, Memorystore, and GCS`
   - **Module location**: `gs://ibm-software-mp-project-test-tf-modules/terraform-enterprise/1.1.3/terraform-enterprise-1.1.3.zip`
4. Set **Default release**: `1.1.3`
5. Click **Save and validate**

### Step 13: Wait for Validation
- GCP Marketplace runs `terraform plan` automatically
- Check **Proposed releases** for status
- Must pass before publishing

---

## Files from Existing Code to Adapt

| Source | Target | Notes |
|--------|--------|-------|
| `terraform/.terraform/modules/tfe/postgresql.tf` | `modules/infrastructure/cloudsql.tf` | Simplify |
| `terraform/.terraform/modules/tfe/redis.tf` | `modules/infrastructure/redis.tf` | Keep auth |
| `terraform/.terraform/modules/tfe/gcs_bucket.tf` | `modules/infrastructure/gcs.tf` | Keep versioning |
| `terraform/.terraform/modules/tfe/iam.tf` | `modules/infrastructure/iam.tf` | Workload Identity |
| `images/tfe/Dockerfile` | `images/tfe/Dockerfile` | Update registry |
| `images/ubbagent/Dockerfile` | `images/ubbagent/Dockerfile` | Keep as-is |

---

## Verification

1. `make terraform/validate` - Syntax check
2. `make terraform/plan` - Plan with test values
3. `make images/build` - Build images to AR
4. `make terraform/upload` - Package ZIP to GCS
5. Submit to Producer Portal for final validation

---

## Key Differences from Click-to-Deploy

| Aspect | Click-to-Deploy (OLD) | Terraform K8s App (NEW) |
|--------|----------------------|------------------------|
| Deployer | envsubst + raw manifests | Terraform + Helm provider |
| Schema | User input properties | Image URI mapping |
| Validation | `mpdev verify` | `terraform plan` |
| Images | GCR (gcr.io) | Artifact Registry (us-docker.pkg.dev) |
| Helm | Not used | Official TFE Helm chart |
| Infrastructure | In-cluster (PostgreSQL, Redis, MinIO) | External (Cloud SQL, Memorystore, GCS) |
| Module location | N/A | Cloud Storage (versioned bucket) |

---

## GCP Partner Portal Configuration

### Deployment Configuration Tab

| Field | Value |
|-------|-------|
| **Helm Chart URL** | `us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace/terraform-enterprise-chart` |
| **Display tag** | `1.1` (semantic minor version) |
| **Module location** | `gs://ibm-software-mp-project-test-tf-modules/terraform-enterprise/1.1.3/terraform-enterprise-1.1.3.zip` |

### Required IAM Roles

Specify these predefined roles in the Partner Portal so users have permission to deploy the infrastructure:

| Role | Purpose |
|------|---------|
| `roles/container.developer` | Deploy to GKE cluster |
| `roles/cloudsql.admin` | Create and manage Cloud SQL instance |
| `roles/redis.admin` | Create and manage Memorystore Redis |
| `roles/storage.admin` | Create and manage GCS bucket |
| `roles/iam.serviceAccountAdmin` | Create service accounts for Workload Identity |
| `roles/iam.serviceAccountUser` | Use service accounts |
| `roles/iam.workloadIdentityUser` | Configure Workload Identity binding |
| `roles/servicenetworking.networksAdmin` | Configure Private Service Access |
| `roles/compute.networkAdmin` | Manage VPC peering for private connectivity |
| `roles/serviceusage.serviceUsageAdmin` | Enable required APIs |

**Copy-paste for Partner Portal:**
```
roles/container.developer
roles/cloudsql.admin
roles/redis.admin
roles/storage.admin
roles/iam.serviceAccountAdmin
roles/iam.serviceAccountUser
roles/iam.workloadIdentityUser
roles/servicenetworking.networksAdmin
roles/compute.networkAdmin
roles/serviceusage.serviceUsageAdmin
```

### Permissions Setup

Before submitting to Partner Portal, ensure public read access is configured:

```bash
# Grant public read access to Artifact Registry (for Helm chart and images)
gcloud artifacts repositories add-iam-policy-binding tfe-marketplace \
  --location=us \
  --project=ibm-software-mp-project-test \
  --member="allUsers" \
  --role="roles/artifactregistry.reader"

# Grant public read access to GCS bucket (for Terraform module)
gsutil iam ch allUsers:objectViewer gs://ibm-software-mp-project-test-tf-modules
```

### Release Checklist

Before submitting a new release to Partner Portal:

1. **Build and push artifacts:**
   ```bash
   make release
   ```
   This will:
   - Build and push TFE + UBB images to Artifact Registry
   - Package and push Helm chart to Artifact Registry
   - Add minor version tags (e.g., `1.1` from `1.1.3`)
   - Package and upload Terraform module to GCS

2. **Or run the test deployment script (includes repackaging):**
   ```bash
   ./scripts/test-deploy.sh
   ```

3. **Verify artifacts exist:**
   ```bash
   # Check images
   gcloud artifacts docker images list us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace --include-tags

   # Check Terraform module
   gsutil ls gs://ibm-software-mp-project-test-tf-modules/terraform-enterprise/
   ```

### Version Tagging

GCP Marketplace requires semantic minor version tags. The Makefile automatically handles this:

- Full version: `1.1.3` (used for builds)
- Minor version: `1.1` (required by Marketplace, added via `make tags/minor`)

Both tags are applied to:
- Helm chart: `terraform-enterprise-chart:1.1.3` and `terraform-enterprise-chart:1.1`
- TFE image: `tfe:1.1.3` and `tfe:1.1`
- UBB image: `ubbagent:1.1.3` and `ubbagent:1.1`
