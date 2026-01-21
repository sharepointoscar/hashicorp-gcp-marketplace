# Terraform Enterprise - GCP Marketplace

HashiCorp Terraform Enterprise for GCP Marketplace using the **Kubernetes App (mpdev)** model with external managed services (Cloud SQL, Memorystore Redis, GCS).

## Architecture

TFE supports two infrastructure provisioning modes:

### Option A: Config Connector (Auto-Provisioning) - Recommended

Uses GCP Config Connector to automatically provision infrastructure as part of the Helm deployment. Infrastructure is created declaratively via Kubernetes CRDs.

```
┌─────────────────────────────────────────────────────────────────┐
│  GCP Marketplace Deployer                                       │
│  └── Helm Chart with Config Connector CRDs                      │
│      ├── ConfigConnectorContext (namespace config)              │
│      ├── SQLInstance (Cloud SQL PostgreSQL)                     │
│      ├── SQLDatabase + SQLUser                                  │
│      ├── RedisInstance (Memorystore Redis)                      │
│      ├── StorageBucket (GCS)                                    │
│      └── TFE Deployment (waits for infrastructure)              │
├─────────────────────────────────────────────────────────────────┤
│  Flow:                                                          │
│  1. Helm renders Config Connector resources                     │
│  2. CC operator provisions GCP infrastructure (10-15 min)       │
│  3. InitContainer waits for resources to be Ready               │
│  4. InitContainer creates ConfigMap/Secret with endpoints       │
│  5. TFE container starts with infrastructure config             │
└─────────────────────────────────────────────────────────────────┘
```

### Option B: Pre-Provisioned Infrastructure (Terraform)

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

### Common Prerequisites

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

### Config Connector Prerequisites (Option A)

When using Config Connector for auto-provisioning:

1. **GKE Cluster with Config Connector addon enabled**:
   ```bash
   gcloud container clusters update CLUSTER_NAME \
     --update-addons ConfigConnector=ENABLED \
     --region REGION
   ```

2. **Google Service Account (GSA) for Config Connector**:
   ```bash
   PROJECT_ID=your-project-id
   GSA_NAME=tfe-config-connector

   # Create GSA
   gcloud iam service-accounts create $GSA_NAME \
     --project=$PROJECT_ID \
     --display-name="TFE Config Connector GSA"

   # Grant permissions for Cloud SQL, Redis, GCS
   for role in cloudsql.admin redis.admin storage.admin monitoring.metricWriter; do
     gcloud projects add-iam-policy-binding $PROJECT_ID \
       --member="serviceAccount:$GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
       --role="roles/$role"
   done
   ```

3. **Private Service Access** configured for VPC (required for private Cloud SQL/Redis):
   ```bash
   # Reserve IP range for private services
   gcloud compute addresses create google-managed-services-default \
     --global --purpose=VPC_PEERING --prefix-length=16 \
     --network=default --project=$PROJECT_ID

   # Create private connection
   gcloud services vpc-peerings connect \
     --service=servicenetworking.googleapis.com \
     --ranges=google-managed-services-default \
     --network=default --project=$PROJECT_ID
   ```

## Quick Start

### Option A: Config Connector (Auto-Provisioning)

```bash
cd products/terraform-enterprise

# 1. Build all images
REGISTRY=gcr.io/$PROJECT_ID TAG=1.1.3 make app/build

# 2. Run validation (uses shared script)
REGISTRY=gcr.io/$PROJECT_ID TAG=1.1.3 \
  ../../shared/scripts/validate-marketplace.sh terraform-enterprise

# 3. Cleanup stuck namespaces (if needed)
../../shared/scripts/validate-marketplace.sh terraform-enterprise --cleanup
```

### Option B: Pre-Provisioned Infrastructure (Terraform)

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
│           ├── config-connector-sql.yaml # Cloud SQL (when CC enabled)
│           ├── config-connector-redis.yaml # Redis (when CC enabled)
│           ├── config-connector-gcs.yaml # GCS bucket (when CC enabled)
│           ├── config-connector-context.yaml # CC namespace config
│           └── rbac.yaml                 # RBAC for CC resources
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
└── terraform/                   # Infrastructure provisioning (Option B)
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

# Cleanup stuck namespaces (handles Config Connector resources)
../../shared/scripts/validate-marketplace.sh terraform-enterprise --cleanup

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

## Config Connector Integration

When `configConnector.enabled=true`, the Helm chart provisions infrastructure automatically using GCP Config Connector CRDs:

| Resource | CRD | Description |
|----------|-----|-------------|
| Cloud SQL | `SQLInstance`, `SQLDatabase`, `SQLUser` | PostgreSQL 16, private IP, auto-resize |
| Redis | `RedisInstance` | Memorystore Redis 7, AUTH enabled |
| GCS | `StorageBucket` | Object storage for TFE |

**InitContainer Flow:**
1. Sets up Workload Identity binding for Config Connector
2. Waits for SQLInstance, RedisInstance, StorageBucket to be Ready (10-15 min)
3. Retrieves infrastructure endpoints (IPs, auth strings)
4. Creates ConfigMap/Secret with TFE environment variables
5. TFE container starts with infrastructure configuration

**Config Connector Values:**
```yaml
configConnector:
  enabled: true
  projectId: "your-project-id"
  googleServiceAccount: "tfe-config-connector@project.iam.gserviceaccount.com"
  networkName: "default"
  sql:
    region: "us-central1"
    tier: "db-custom-4-16384"
    diskSize: 50
  redis:
    region: "us-central1"
    tier: "STANDARD_HA"
    memorySizeGb: 4
```

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

### Config Connector (Option A)
| Property | Description |
|----------|-------------|
| `configConnector.enabled` | Enable auto-provisioning (default: true) |
| `configConnector.projectId` | GCP project ID |
| `configConnector.googleServiceAccount` | GSA for Config Connector |

### Pre-provisioned Infrastructure (Option B)
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
# Use the shared script to clean up Config Connector resources and namespaces
../../shared/scripts/validate-marketplace.sh terraform-enterprise --cleanup

# Or manually
kubectl delete ns apptest-*
```

### Config Connector resources stuck in "Unmanaged" status

This indicates the Config Connector controller isn't managing the namespace:

```bash
# Check ConfigConnectorContext
kubectl get configconnectorcontext -n <namespace>

# Check if controller is running
kubectl get pods -n cnrm-system -l cnrm.cloud.google.com/scoped-namespace=<namespace>

# Verify GSA has correct permissions
gcloud iam service-accounts get-iam-policy \
  tfe-config-connector@$PROJECT_ID.iam.gserviceaccount.com
```

### Config Connector resources failing with 403

The GSA lacks permissions. Grant required roles:

```bash
for role in cloudsql.admin redis.admin storage.admin; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:tfe-config-connector@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/$role"
done
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
