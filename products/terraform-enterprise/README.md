# Terraform Enterprise - GCP Marketplace

HashiCorp Terraform Enterprise for GCP Marketplace using the **Kubernetes App (mpdev)** model with a **self-contained architecture**. All services run in-cluster — no external Cloud SQL, Memorystore, or GCS required.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  GKE Cluster                                                     │
│                                                                  │
│  ┌──────────────────────┐  ┌──────────────────┐                 │
│  │ TFE Deployment       │  │ embedded-postgres │                 │
│  │  ├─ terraform-enterprise  │  (SSL enabled)     │                 │
│  │  └─ ubbagent (sidecar)│  └──────────────────┘                 │
│  └──────────────────────┘  ┌──────────────────┐                 │
│                             │ embedded-redis   │                 │
│  Init containers:           └──────────────────┘                 │
│  1. wait-for-postgres       ┌──────────────────┐                 │
│  2. wait-for-redis          │ embedded-minio   │                 │
│  3. wait-for-minio          │ (S3-compatible)  │                 │
│  4. create-minio-bucket     └──────────────────┘                 │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **GCP Project** with billing enabled
2. **GKE Cluster** (1.33+ recommended)
3. **Artifact Registry** authenticated:
   ```bash
   gcloud auth configure-docker us-docker.pkg.dev
   ```
4. **HashiCorp registry** authenticated (for building TFE image):
   ```bash
   export TFE_LICENSE=$(cat "terraform exp Mar 31 2026.hclic")
   make registry/login
   ```
5. **mpdev installed** (for verification):
   ```bash
   docker pull gcr.io/cloud-marketplace-tools/k8s/dev
   ```

## Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `REGISTRY` | Artifact Registry path | `us-docker.pkg.dev/$PROJECT_ID/tfe-marketplace` |
| `TAG` | Image version tag | `1.1.3` |
| `MP_SERVICE_NAME` | **REQUIRED.** GCP Marketplace service annotation | See values below |

**MP_SERVICE_NAME values by environment:**
- Test: `MP_SERVICE_NAME=services/terraform-enterprise.endpoints.ibm-software-mp-project-test.cloud.goog`
- Production: `MP_SERVICE_NAME=services/ibmterraformselfmanagedbyol.endpoints.ibm-software-mp-project.cloud.goog`

> **WARNING:** `MP_SERVICE_NAME` has no default. The build will fail if it is not set. Every image MUST be annotated with the correct service name for the target environment.

## Quick Start

```bash
cd products/terraform-enterprise

# Build all images (MUST set MP_SERVICE_NAME)
REGISTRY=us-docker.pkg.dev/$PROJECT_ID/tfe-marketplace TAG=1.1.3 \
  MP_SERVICE_NAME=services/<service-name>.endpoints.$PROJECT_ID.cloud.goog \
  make app/build

# Run mpdev verify
REGISTRY=us-docker.pkg.dev/$PROJECT_ID/tfe-marketplace TAG=1.1.3 \
  make app/verify

# Full release pipeline (clean + build + tag versions)
REGISTRY=us-docker.pkg.dev/$PROJECT_ID/tfe-marketplace TAG=1.1.3 \
  MP_SERVICE_NAME=services/<service-name>.endpoints.$PROJECT_ID.cloud.goog \
  make release
```

## Shared Validation Script

```bash
# Full validation pipeline (build + install + verify)
REGISTRY=us-docker.pkg.dev/$PROJECT_ID/tfe-marketplace TAG=1.1.3 \
  MP_SERVICE_NAME=services/<service-name>.endpoints.$PROJECT_ID.cloud.goog \
  ../../shared/scripts/validate-marketplace.sh terraform-enterprise

# Clean Artifact Registry images before building
REGISTRY=us-docker.pkg.dev/$PROJECT_ID/tfe-marketplace TAG=1.1.3 \
  MP_SERVICE_NAME=services/<service-name>.endpoints.$PROJECT_ID.cloud.goog \
  ../../shared/scripts/validate-marketplace.sh terraform-enterprise --gcr-clean
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
│           ├── _helpers.tpl             # Template helpers + env var mapping
│           ├── application.yaml         # GCP Marketplace Application CRD
│           ├── config-map.yaml          # TFE configuration
│           ├── deployment.yaml          # TFE Deployment with init containers
│           ├── embedded-minio.yaml      # In-cluster MinIO (S3-compatible)
│           ├── embedded-postgres.yaml   # In-cluster PostgreSQL (SSL enabled)
│           ├── embedded-redis.yaml      # In-cluster Redis
│           ├── secret.yaml              # TLS and credential secrets
│           ├── service.yaml             # TFE service (LoadBalancer)
│           ├── ubbagent-config.yaml     # Usage-based billing config
│           └── ...                      # ingress, pdb, rbac, etc.
├── deployer/
│   └── Dockerfile               # Deployer image (deployer_helm base)
├── apptest/
│   ├── deployer/
│   │   └── schema.yaml          # Test schema with defaults
│   └── tester/
│       ├── Dockerfile
│       ├── tester.sh
│       └── tests/
│           └── health-check.yaml
├── images/
│   ├── tfe/Dockerfile           # TFE container image
│   └── ubbagent/Dockerfile      # Usage-based billing agent
├── test-certs/                  # Self-signed test certificates
└── terraform/                   # Infrastructure provisioning (legacy)
```

## Makefile Targets

All build targets require `REGISTRY`, `TAG`, and `MP_SERVICE_NAME`:

```bash
make app/build         # Build all images (tfe, ubbagent, deployer, tester)
make app/verify        # Run mpdev verify
make app/install       # Run mpdev install
make helm/lint         # Lint Helm chart
make helm/template     # Render Helm templates
make ar/tag-versions   # Add major/minor version tags
make ar/clean          # Delete images from Artifact Registry (current version)
make ar/clean-all      # Delete ALL images from Artifact Registry
make clean             # Clean local build artifacts
make info              # Display version and artifact info
make registry/login    # Login to HashiCorp registry
make release           # Clean, build, push, and tag all versions
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
| `tfeLicense` | TFE license |
| `encryptionPassword` | Encryption password (16+ chars) |

### TLS Configuration
| Property | Description |
|----------|-------------|
| `tlsCertificate` | TLS cert (base64) |
| `tlsPrivateKey` | TLS key (base64) |
| `tlsCACertificate` | CA cert (base64) |

### Service Account
| Property | Description |
|----------|-------------|
| `tfeServiceAccount` | K8s service account for in-cluster operations |
| `reportingSecret` | GCP Marketplace reporting secret |

## Troubleshooting

### mpdev verify fails with timeout

TFE requires >600 seconds to fully start. The deployer sets `WAIT_FOR_READY_TIMEOUT=1800`.

Check pod status:
```bash
kubectl get pods -n <namespace>
kubectl logs -n <namespace> <pod> -c terraform-enterprise
```

### Check embedded services

```bash
kubectl logs -n <namespace> -l app=embedded-postgres
kubectl logs -n <namespace> -l app=embedded-redis
kubectl logs -n <namespace> -l app=embedded-minio
```

### Health check endpoint

```bash
kubectl get svc -n <namespace>
curl -k https://<LB_IP>/_health_check
# Expected: {"postgres":"UP","redis":"UP","vault":"UP"}
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
gcloud artifacts docker images describe \
  us-docker.pkg.dev/$PROJECT_ID/tfe-marketplace/terraform-enterprise:1.1.3 \
  --format=yaml | grep service.name
```

All images must have:
```
com.googleapis.cloudmarketplace.product.service.name=<MP_SERVICE_NAME>
```

## Version Synchronization

These files must have matching versions:
1. `schema.yaml` → `publishedVersion: '1.1.3'`
2. `apptest/deployer/schema.yaml` → `publishedVersion: '1.1.3'`
3. `chart/terraform-enterprise/Chart.yaml` → `version: 1.1.3` and `appVersion: "1.1.3"`
4. `Makefile` → `VERSION ?= 1.1.3`

## GCP Marketplace Requirements

Images must be:
- Single architecture: `linux/amd64`
- Docker V2 manifests: `--provenance=false --sbom=false`
- Annotated with `com.googleapis.cloudmarketplace.product.service.name` (**REQUIRED**, set via `MP_SERVICE_NAME`)
- Tagged with semantic versions (e.g., `1.1.3`, `1.1`, and `1`)
