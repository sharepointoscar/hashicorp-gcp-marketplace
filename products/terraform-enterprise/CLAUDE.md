# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

**Prerequisites:**
```bash
# Authenticate to GCP and HashiCorp registry
gcloud auth login && gcloud auth configure-docker us-docker.pkg.dev
docker login images.releases.hashicorp.com -u terraform -p $TFE_LICENSE
```

**Standard Build Workflow:**
```bash
# Build all images (tfe, ubbagent, deployer, tester) - uses Artifact Registry
# MP_SERVICE_NAME is REQUIRED — images MUST be annotated with the correct service name
REGISTRY=us-docker.pkg.dev/$PROJECT_ID/tfe-marketplace TAG=1.1.3 \
  MP_SERVICE_NAME=services/<service-name>.endpoints.$PROJECT_ID.cloud.goog \
  make app/build

# Run mpdev verify
REGISTRY=us-docker.pkg.dev/$PROJECT_ID/tfe-marketplace TAG=1.1.3 make app/verify
```

**MP_SERVICE_NAME values by environment:**
- Test: `MP_SERVICE_NAME=services/terraform-enterprise.endpoints.ibm-software-mp-project-test.cloud.goog`
- Production: `MP_SERVICE_NAME=services/ibmterraformselfmanagedbyol.endpoints.ibm-software-mp-project.cloud.goog`

**Individual targets:**
- `make app/build` - Build all images (tfe, ubbagent, deployer, tester)
- `make app/verify` - Run mpdev verify
- `make app/install` - Run mpdev install (test deployment)
- `make helm/lint` - Lint Helm chart
- `make ar/clean` - Delete images from Artifact Registry (current version)
- `make ar/clean-all` - Delete ALL images from Artifact Registry
- `make ar/tag-minor` - Add minor version tags (e.g., 1.1 from 1.1.3)
- `make clean` - Clean local build artifacts
- `make registry/login` - Login to HashiCorp registry (requires TFE_LICENSE env var)

## Architecture

This is a GCP Marketplace deployer for HashiCorp Terraform Enterprise using **Kubernetes App (mpdev)** model with a **self-contained architecture**. All services run in-cluster:

- **PostgreSQL** — embedded-postgres pod (port 5432)
- **Redis** — embedded-redis pod (port 6379)
- **Object Storage** — embedded-minio pod (S3-compatible, port 9000)

No external Cloud SQL, Memorystore Redis, or GCS bucket required.

### Application Deployment
- Deployer: `deployer/Dockerfile` (uses `deployer_helm` base)
- Chart: `chart/terraform-enterprise/`
- User: GCP Marketplace UI or mpdev CLI

### Image Build Pipeline
```
images/tfe/Dockerfile          → us-docker.pkg.dev/.../tfe-marketplace/terraform-enterprise:TAG
images/ubbagent/Dockerfile     → us-docker.pkg.dev/.../tfe-marketplace/terraform-enterprise/ubbagent:TAG
deployer/Dockerfile            → us-docker.pkg.dev/.../tfe-marketplace/terraform-enterprise/deployer:TAG
apptest/tester/Dockerfile      → us-docker.pkg.dev/.../tfe-marketplace/terraform-enterprise/tester:TAG
```

### Key Files
- `schema.yaml` - GCP Marketplace schema defining user inputs
- `apptest/deployer/schema.yaml` - Test schema with default values for mpdev verify
- `chart/terraform-enterprise/` - Helm chart for TFE deployment
- `deployer/Dockerfile` - mpdev deployer using deployer_helm base

### Embedded Services (chart templates)
- `chart/.../templates/embedded-postgres.yaml` - PostgreSQL deployment + service
- `chart/.../templates/embedded-redis.yaml` - Redis deployment + service
- `chart/.../templates/embedded-minio.yaml` - MinIO deployment + service (S3-compatible)

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

# Check embedded services
kubectl logs -n <namespace> -l app=embedded-postgres
kubectl logs -n <namespace> -l app=embedded-redis
kubectl logs -n <namespace> -l app=embedded-minio

# Health check endpoint
curl -k https://<lb-ip>/_health_check
# Expected: {"postgres":"UP","redis":"UP","vault":"UP"}
```

**Common mpdev verify errors and fixes:**

| Error | Cause | Fix |
|-------|-------|-----|
| `Invalid schema publishedVersion` | publishedVersion needs full semver | Use `1.1.3` not `1.1` in both schema.yaml files |
| `ImagePullBackOff` | Image tag doesn't exist in registry | Run `make app/build` with matching TAG |
| `ImagePullBackOff (403)` | Cluster can't reach registry in different project | Use correct cluster for the target project |
| `pq: SSL is not enabled on the server` | Embedded PostgreSQL SSL not configured | SSL is now enabled via init container — should not occur |
| `vault-manager crash loop` | Missing encryption password or stale data | Ensure encryption password is set |
| `Startup probe timeout` | TFE takes too long to start | Deployer sets WAIT_FOR_READY_TIMEOUT=1800 |
| MinIO pod 1/2 ready | Sidecar init container blocks Service endpoints | Bucket creation must be in TFE init containers, NOT as a MinIO sidecar |

### TLS Certificate Handling
TLS secrets are created from flat GCP Marketplace schema properties in `secret.yaml`:
- `tlsCertificate` + `tlsPrivateKey` → `terraform-enterprise-tls-gcp` secret (kubernetes.io/tls)
- `tlsCACertificate` → `terraform-enterprise-ca-gcp` secret (Opaque, key: ca.crt)
- The test schema (`apptest/deployer/schema.yaml`) includes self-signed test certs as defaults

### Init Container Sequence (deployment.yaml)
1. `wait-for-postgres` — polls `embedded-postgres:5432`
2. `wait-for-redis` — polls `embedded-redis:6379`
3. `wait-for-minio` — polls `embedded-minio:9000`
4. `create-minio-bucket` — runs `mc mb` to create `tfe-objects` bucket

**Pre-flight checklist before running mpdev verify:**
1. Version files match: `schema.yaml`, `apptest/deployer/schema.yaml`, `Makefile`
2. Images built with same TAG as `publishedVersion`
3. Previous test namespaces cleaned up: `kubectl delete ns apptest-*`

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
│       └── templates/
│           ├── deployment.yaml          # TFE main deployment
│           ├── embedded-postgres.yaml   # In-cluster PostgreSQL
│           ├── embedded-redis.yaml      # In-cluster Redis
│           └── embedded-minio.yaml      # In-cluster MinIO (S3)
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
└── scripts/
    └── release.sh
```
