# Terraform Enterprise - GCP Marketplace

HashiCorp Terraform Enterprise for GCP Marketplace using the **Kubernetes App (mpdev)** model with external managed services (Cloud SQL, Memorystore Redis, GCS).

## Architecture

Infrastructure is provisioned separately using Terraform before deploying TFE.

```
┌─────────────────────────────────────────────────────────────────┐
│  Phase 1: Infrastructure (Terraform)                            │
│  └── terraform/ directory                                       │
│      ├── Cloud SQL PostgreSQL                                   │
│      ├── Memorystore Redis                                      │
│      └── GCS Bucket                                             │
├─────────────────────────────────────────────────────────────────┤
│  Phase 2: Application (mpdev deployer)                          │
│  └── Helm chart via deployer_helm                               │
│      ├── TFE Deployment                                         │
│      ├── UBB Agent Sidecar                                      │
│      └── Services, ConfigMaps, Secrets                          │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **GCP Project** with billing enabled
2. **GKE Cluster** (1.33+ recommended)
3. **Docker authenticated** to GCR:
   ```bash
   gcloud auth configure-docker
   ```
4. **HashiCorp registry authenticated** (for building TFE image):
   ```bash
   export TFE_LICENSE=$(cat "terraform exp Mar 31 2026.hclic")
   make registry/login
   ```
5. **mpdev installed** (for verification):
   ```bash
   gcloud components install kubectl
   docker pull gcr.io/cloud-marketplace-tools/k8s/dev
   ```

## Quick Start

```bash
# 1. Provision infrastructure first
cd products/terraform-enterprise/terraform
terraform init
terraform apply -var="project_id=YOUR_PROJECT_ID"

# Get values for Marketplace form
terraform output marketplace_inputs

# 2. Build images
cd products/terraform-enterprise
REGISTRY=gcr.io/$PROJECT_ID TAG=1.1.3 make app/build

# 3. Run validation
REGISTRY=gcr.io/$PROJECT_ID TAG=1.1.3 make app/verify
```

## Directory Structure

```
products/terraform-enterprise/
├── Makefile                     # Build targets for mpdev model
├── schema.yaml                  # GCP Marketplace schema (user inputs)
├── chart/
│   └── terraform-enterprise/    # Helm chart for TFE
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml           # TFE Deployment with initContainer
│           └── rbac.yaml                 # RBAC for resources
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
│   ├── tfe/Dockerfile           # TFE container image
│   └── ubbagent/Dockerfile      # Usage-based billing agent
└── terraform/                   # Infrastructure provisioning
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── modules/infrastructure/
```

## Makefile Targets

```bash
make app/build         # Build all images (tfe, ubbagent, deployer, tester)
make app/verify        # Run mpdev verify
make app/install       # Run mpdev install
make helm/lint         # Lint Helm chart
make gcr/tag-versions  # Add major/minor version tags
make gcr/clean         # Delete images from GCR
make clean             # Clean local build artifacts
make info              # Display version and artifact info
make registry/login    # Login to HashiCorp registry
make release           # Clean, build, and tag all versions
```

## Shared Validation Script

```bash
# Full validation pipeline (build + verify)
REGISTRY=gcr.io/$PROJECT_ID TAG=1.1.3 \
  ../../shared/scripts/validate-marketplace.sh terraform-enterprise

# Clean GCR images before building
REGISTRY=gcr.io/$PROJECT_ID TAG=1.1.3 \
  ../../shared/scripts/validate-marketplace.sh terraform-enterprise --gcr-clean
```

## Images Built

| Image | Description |
|-------|-------------|
| `$REGISTRY/terraform-enterprise:$TAG` | Main TFE application |
| `$REGISTRY/terraform-enterprise/ubbagent:$TAG` | Usage-based billing agent |
| `$REGISTRY/terraform-enterprise/deployer:$TAG` | mpdev deployer (Helm-based) |
| `$REGISTRY/terraform-enterprise/tester:$TAG` | mpdev tester for verification |

## Schema Properties

User inputs defined in `schema.yaml`:

### Core Settings
| Property | Description |
|----------|-------------|
| `name` | Application instance name |
| `namespace` | Kubernetes namespace |
| `hostname` | TFE FQDN |
| `license` | TFE license (base64) |
| `encryptionPassword` | Encryption password (16+ chars) |

### TLS Configuration
| Property | Description |
|----------|-------------|
| `tlsCertificate` | TLS cert (base64) |
| `tlsPrivateKey` | TLS key (base64) |
| `tlsCACertificate` | CA cert (base64) |

### Pre-provisioned Infrastructure
| Property | Description |
|----------|-------------|
| `databaseHost` | Cloud SQL PostgreSQL private IP |
| `databaseName` | Database name (default: tfe) |
| `databaseUser` | Database user (default: tfe) |
| `databasePassword` | Database password |
| `redisHost` | Memorystore Redis private IP |
| `redisPassword` | Redis AUTH string |
| `objectStorageBucket` | GCS bucket name |
| `objectStorageProject` | GCP project ID |

### Service Account
| Property | Description |
|----------|-------------|
| `serviceAccount` | K8s service account |
| `reportingSecret` | GCP Marketplace reporting secret |

## Troubleshooting

### mpdev verify fails with timeout

TFE requires >600 seconds to fully start. The deployer sets `WAIT_FOR_READY_TIMEOUT=1800`.

Check pod status:
```bash
kubectl get pods -n <namespace>
kubectl logs -n <namespace> <pod> -c terraform-enterprise
```

### Health check endpoint

```bash
kubectl get svc -n <namespace>
curl -k https://<LB_IP>/_health_check
# Expected: {"postgres":"UP","redis":"UP","vault":"UP"}
```

### Vault manager crash loop

This usually indicates stale encryption data. Clean vault tables:
```bash
# Flush Redis
kubectl run redis-flush --rm -it --restart=Never --image=redis:7 -- \
  redis-cli -h <REDIS_IP> -a "<password>" FLUSHALL

# Truncate vault tables
kubectl run psql-cleanup --rm -i --restart=Never --image=postgres:15 -- \
  psql "postgresql://tfe:<password>@<DB_IP>:5432/tfe?sslmode=require" <<EOF
TRUNCATE vault.vault_kv_store CASCADE;
TRUNCATE vault.vault_ha_locks CASCADE;
EOF
```

### Clean up test namespaces

```bash
# Use the shared script
../../shared/scripts/validate-marketplace.sh terraform-enterprise --cleanup

# Or manually
kubectl delete ns apptest-*
```

### Verify image annotations

```bash
docker manifest inspect gcr.io/$PROJECT_ID/terraform-enterprise:1.1.3 | jq '.annotations'
```

All images must have:
```
com.googleapis.cloudmarketplace.product.service.name=services/tfe-self-managed.endpoints.PROJECT_ID.cloud.goog
```

## Version Synchronization

These files must have matching versions:
1. `schema.yaml` → `publishedVersion: '1.1.3'`
2. `apptest/deployer/schema.yaml` → `publishedVersion: '1.1.3'`
3. `Makefile` → `VERSION ?= 1.1.3`

## GCP Marketplace Requirements

Images must be:
- Single architecture: `linux/amd64`
- Docker V2 manifests: `--provenance=false --sbom=false`
- Annotated with `com.googleapis.cloudmarketplace.product.service.name`
- Tagged with semantic versions (e.g., `1.1.3` and `1.1`)
