# Terraform Enterprise - GCP Marketplace

HashiCorp Terraform Enterprise for GCP Marketplace using the **Terraform K8s App** model with external managed services (Cloud SQL, Memorystore Redis, GCS).

---

## Prerequisites

Before running the workflow, ensure you have:

1. **GCP Project**: `ibm-software-mp-project-test`
2. **GKE Cluster**: `vault-mp-test` in `us-central1`
3. **Artifact Registry**: Create if not exists:
   ```bash
   gcloud artifacts repositories create tfe-marketplace \
     --repository-format=docker \
     --location=us \
     --project=ibm-software-mp-project-test
   ```
4. **GCS Bucket**: Create if not exists (with versioning required by Marketplace):
   ```bash
   gsutil mb -p ibm-software-mp-project-test gs://ibm-software-mp-project-test-tf-modules
   gsutil versioning set on gs://ibm-software-mp-project-test-tf-modules
   ```
5. **Docker authenticated** to GCP:
   ```bash
   gcloud auth configure-docker us-docker.pkg.dev
   ```
6. **HashiCorp registry authenticated** (for building TFE image):
   ```bash
   export TFE_LICENSE=$(cat "terraform exp Mar 31 2026.hclic")
   make registry/login
   ```

---

## Complete Workflow

### Step 1: Build and Push All Artifacts

```bash
cd products/terraform-enterprise

# Build images, push Helm chart, upload TF module
./scripts/release.sh --build
```

This will:
- Build and push TFE + UBB images to Artifact Registry
- Package and push Helm chart to Artifact Registry
- Add minor version tags (e.g., `1.1` from `1.1.3`)
- Package and upload Terraform module ZIP to GCS

### Step 2: Simulate Portal Validation

GCP Marketplace validates by running `terraform plan`. Simulate locally:

```bash
terraform init

terraform plan -var-file=marketplace_test.tfvars \
  -var="project_id=ibm-software-mp-project-test" \
  -var="tfe_image_repo=us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace/tfe" \
  -var="tfe_image_tag=1.1.3" \
  -var="ubbagent_image_repo=us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace/ubbagent" \
  -var="ubbagent_image_tag=1.1.3"
```

> **Note:** The image variables are normally set by the Marketplace portal via `schema.yaml`. For local simulation, we pass them explicitly.

If this succeeds, the portal's "Save and validate" will also succeed.

### Step 3: Deploy to GKE Cluster (Optional)

To actually deploy TFE to the cluster:

```bash
./scripts/release.sh --deploy
```

This runs `terraform apply` with the test values.

### Step 4: Get Portal Configuration Info

```bash
./scripts/release.sh --info
```

This displays all values needed for the Producer Portal.

---

## Release Script Options

```bash
./scripts/release.sh [OPTIONS]

Options:
  --clean    Delete all artifacts from AR and GCS
  --build    Build and push all artifacts
  --deploy   Deploy to GKE cluster (terraform apply)
  --info     Display Partner Portal configuration
  --all      Clean, build, deploy, and display info
  --help     Show help

Default (no flags): --build --info
```

### Common Workflows

```bash
# Full release (build + show portal info)
./scripts/release.sh

# Clean slate rebuild
./scripts/release.sh --all

# Just show what to paste in portal
./scripts/release.sh --info

# Deploy after making changes
./scripts/release.sh --build --deploy
```

---

## Directory Structure

```
products/terraform-enterprise/
├── main.tf                      # Providers, API enablement
├── gke.tf                       # GKE cluster data source
├── helm.tf                      # Helm release for TFE
├── variables.tf                 # Input variables
├── outputs.tf                   # Deployment outputs
├── versions.tf                  # Terraform/provider versions (>= 1.3)
├── schema.yaml                  # Image URI mapping for Marketplace
├── marketplace_test.tfvars      # Test values for portal validation
├── Makefile                     # Build targets
├── scripts/
│   └── release.sh               # Main release/deploy script
├── helm/                        # Helm chart (pushed to AR)
├── images/
│   ├── tfe/Dockerfile           # TFE container image
│   └── ubbagent/Dockerfile      # Usage-based billing agent
├── modules/infrastructure/      # Cloud SQL, Redis, GCS resources
└── test-certs/                  # Self-signed TLS certs for testing
```

---

## Makefile Targets

```bash
make images/build      # Build container images
make helm/push         # Package and push Helm chart
make terraform/upload  # Package and upload TF module
make terraform/plan    # Run terraform plan
make ar/clean          # Delete images from Artifact Registry
make clean             # Clean local build artifacts
make info              # Display version and artifact info
```

---

## GCP Producer Portal Configuration

After running `./scripts/release.sh --info`, use these values:

### Deployment Configuration Tab

| Field | Value |
|-------|-------|
| **Helm Chart URL** | `us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace/terraform-enterprise-chart` |
| **Display tag** | `1.1` |
| **Module location** | `gs://ibm-software-mp-project-test-tf-modules/terraform-enterprise/1.1.3/terraform-enterprise-1.1.3.zip` |

### Required IAM Roles

| Role | Purpose |
|------|---------|
| `roles/container.developer` | Deploy to GKE cluster |
| `roles/cloudsql.admin` | Create Cloud SQL instance |
| `roles/redis.admin` | Create Memorystore Redis |
| `roles/storage.admin` | Create GCS bucket |
| `roles/iam.serviceAccountAdmin` | Create service accounts |
| `roles/iam.serviceAccountUser` | Use service accounts |
| `roles/iam.workloadIdentityUser` | Configure Workload Identity |
| `roles/servicenetworking.networksAdmin` | Configure Private Service Access |
| `roles/compute.networkAdmin` | Manage VPC peering |
| `roles/serviceusage.serviceUsageAdmin` | Enable required APIs |

---

## Troubleshooting

### Portal Error: "Failed to execute terraform plan"

**Cause**: Terraform version constraint incompatible with Infrastructure Manager.

**Fix**: Ensure `versions.tf` has `required_version = ">= 1.3"`. Infrastructure Manager supports 1.5.7, 1.4.7, and 1.3.10.

### Health Check

```bash
kubectl get svc -n terraform-enterprise
curl -k https://<LB_IP>/_health_check
# Expected: {"postgres":"UP","redis":"UP","vault":"UP"}
```

### Check Pod Status

```bash
kubectl get pods -n terraform-enterprise
kubectl logs -n terraform-enterprise <pod-name> -c terraform-enterprise
```

### Verify Image Annotations

```bash
docker manifest inspect us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace/tfe:1.1.3 | jq '.annotations'
```

All images must have:
```
com.googleapis.cloudmarketplace.product.service.name=services/tfe-self-managed.endpoints.ibm-software-mp-project-test.cloud.goog
```
