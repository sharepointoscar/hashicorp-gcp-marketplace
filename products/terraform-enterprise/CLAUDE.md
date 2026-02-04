# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

**Prerequisites:**
```bash
# Authenticate to GCP and HashiCorp registry
gcloud auth login && gcloud auth configure-docker
docker login images.releases.hashicorp.com -u terraform -p $TFE_LICENSE
```

**Standard Build Workflow:**
```bash
# Build all images (tfe, ubbagent, deployer, tester)
REGISTRY=gcr.io/$PROJECT_ID TAG=1.1.3 make app/build

# Run mpdev verify
REGISTRY=gcr.io/$PROJECT_ID TAG=1.1.3 make app/verify

# Or use the release script
./scripts/release.sh --build --verify
```

**Individual targets:**
- `make app/build` - Build all images (tfe, ubbagent, deployer, tester)
- `make app/verify` - Run mpdev verify
- `make app/install` - Run mpdev install (test deployment)
- `make helm/lint` - Lint Helm chart
- `make gcr/clean` - Delete all images from GCR
- `make gcr/tag-minor` - Add minor version tags (e.g., 1.1 from 1.1.3)
- `make clean` - Clean local build artifacts
- `make registry/login` - Login to HashiCorp registry (requires TFE_LICENSE env var)

## Architecture

This is a GCP Marketplace deployer for HashiCorp Terraform Enterprise using **Kubernetes App (mpdev)** model with **External Services mode** (Cloud SQL PostgreSQL, Memorystore Redis, GCS bucket).

### Infrastructure Provisioning

Infrastructure must be pre-provisioned using Terraform before deploying TFE:
- Location: `terraform/` directory
- Resources: Cloud SQL, Memorystore Redis, GCS bucket

**Terraform commands:**
```bash
cd terraform
terraform init
terraform apply -var="project_id=YOUR_PROJECT"
terraform output marketplace_inputs  # Values for Marketplace form
```

### Application Deployment
- Deployer: `deployer/Dockerfile` (uses `deployer_helm` base)
- Chart: `chart/terraform-enterprise/`
- User: GCP Marketplace UI or mpdev CLI

### Image Build Pipeline
```
images/tfe/Dockerfile          → gcr.io/.../terraform-enterprise:TAG
images/ubbagent/Dockerfile     → gcr.io/.../terraform-enterprise/ubbagent:TAG
deployer/Dockerfile            → gcr.io/.../terraform-enterprise/deployer:TAG
apptest/tester/Dockerfile      → gcr.io/.../terraform-enterprise/tester:TAG
```

### Key Files
- `schema.yaml` - GCP Marketplace schema defining user inputs
- `apptest/deployer/schema.yaml` - Test schema with default values for mpdev verify
- `chart/terraform-enterprise/` - Helm chart for TFE deployment
- `deployer/Dockerfile` - mpdev deployer using deployer_helm base
- `terraform/` - Infrastructure provisioning (Cloud SQL, Redis, GCS)

### Shared Makefiles
- `../../shared/Makefile.common` - Docker build flags for GCP Marketplace compliance

### Version Synchronization
All files must have matching versions:
- `schema.yaml` → `publishedVersion: '1.1.3'`
- `apptest/deployer/schema.yaml` → `publishedVersion: '1.1.3'`
- `Makefile` → `VERSION ?= 1.1.3`

Image tags use full semver (e.g., `1.1.3`) with an additional **minor version** alias (e.g., `1.1`).

## Debugging mpdev verify

```bash
# Check pod status
kubectl get pods -n <namespace>

# Check TFE container logs
kubectl logs -n <namespace> <pod-name> -c terraform-enterprise

# Check vault-manager logs (common failure point)
kubectl logs -n <namespace> <pod-name> -c terraform-enterprise | grep vault

# Health check endpoint
curl -k https://<lb-ip>/_health_check
# Expected: {"postgres":"UP","redis":"UP","vault":"UP"}
```

**Common mpdev verify errors and fixes:**

| Error | Cause | Fix |
|-------|-------|-----|
| `Invalid schema publishedVersion` | publishedVersion needs full semver | Use `1.1.3` not `1.1` in both schema.yaml files |
| `ImagePullBackOff` | Image tag doesn't exist in GCR | Run `make app/build` with matching TAG |
| `vault-manager crash loop` | Missing encryption password or stale data | Ensure encryption password is set. Clean vault_* tables in PostgreSQL and flush Redis |
| `Startup probe timeout` | TFE takes too long to start | Deployer sets WAIT_FOR_READY_TIMEOUT=1800 |

**Pre-flight checklist before running mpdev verify:**
1. Version files match: `schema.yaml`, `apptest/deployer/schema.yaml`, `Makefile`
2. Images built with same TAG as `publishedVersion`
3. Previous test namespaces cleaned up: `kubectl delete ns apptest-*`
4. Vault data cleaned for fresh install (see below)

**Cleaning stale vault data (required for fresh mpdev verify runs):**
```bash
# Flush Redis
kubectl run redis-flush --rm -it --restart=Never --image=redis:7 -- \
  redis-cli -h <REDIS_IP> -a "<redis-password>" FLUSHALL

# Truncate vault tables in PostgreSQL (note: vault uses its own schema)
kubectl run psql-cleanup --rm -i --restart=Never --image=postgres:15 -- \
  psql "postgresql://tfe:<url-encoded-password>@<DB_IP>:5432/tfe?sslmode=require" <<EOF
TRUNCATE vault.vault_kv_store CASCADE;
TRUNCATE vault.vault_ha_locks CASCADE;
EOF
```

## GCP Marketplace Requirements

Images must be:
- Single architecture (`linux/amd64`)
- Docker V2 manifests (`--provenance=false --sbom=false`)
- Annotated with `com.googleapis.cloudmarketplace.product.service.name`
- Tagged with semantic minor version (e.g., `1.1` not `latest`)

## Directory Structure

```
products/terraform-enterprise/
├── Makefile                     # Build targets for mpdev model
├── schema.yaml                  # GCP Marketplace schema (user inputs)
├── chart/
│   └── terraform-enterprise/    # Helm chart for TFE
├── deployer/
│   └── Dockerfile               # Deployer image (deployer_helm base)
├── apptest/
│   ├── deployer/
│   │   └── schema.yaml          # Test schema with defaults
│   └── tester/
│       ├── Dockerfile
│       ├── tester.sh
│       └── tests/
├── images/
│   ├── tfe/Dockerfile
│   └── ubbagent/Dockerfile
├── terraform/                   # Infrastructure provisioning
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   ├── gke.tf
│   └── modules/infrastructure/
└── scripts/
    └── release.sh
```
