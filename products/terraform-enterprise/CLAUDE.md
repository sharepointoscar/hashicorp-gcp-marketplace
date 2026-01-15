# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

**Prerequisites:**
```bash
# Authenticate to GCP and HashiCorp registry
gcloud auth login && gcloud auth configure-docker
docker login images.releases.hashicorp.com -u terraform -p $TFE_LICENSE
```

**Standard Validation Workflow (USE THIS):**
```bash
# Full validation pipeline - builds, schema check, install, verify, vuln scan
REGISTRY=gcr.io/$PROJECT_ID TAG=1.22.1 \
  ../../shared/scripts/validate-marketplace.sh terraform-enterprise

# With --keep-deployment to inspect after validation
REGISTRY=gcr.io/$PROJECT_ID TAG=1.22.1 \
  ../../shared/scripts/validate-marketplace.sh terraform-enterprise --keep-deployment
```

**Always use the shared validation script** for all products. It runs the complete pipeline:
1. Prerequisites check
2. mpdev doctor (environment health)
3. Build all images (`make app/build`)
4. Schema verification
5. mpdev install (test deployment)
6. mpdev verify (full verification)
7. Vulnerability scan check

**Individual targets (use only when needed):**
```bash
# Full release (clean, build all images, tag with minor version)
REGISTRY=gcr.io/$PROJECT_ID TAG=1.22.1 make release

# Build only (no clean)
REGISTRY=gcr.io/$PROJECT_ID TAG=1.22.1 make app/build

# Run GCP Marketplace verification (prefer shared script instead)
REGISTRY=gcr.io/$PROJECT_ID TAG=1.22.1 make mpdev/verify
```

**Individual targets:**
- `make gcr/clean` - Delete all images from GCR
- `make gcr/tag-minor` - Add minor version tags (e.g., 1.22 from 1.22.1)
- `make clean` - Clean local build artifacts
- `make registry/login` - Login to HashiCorp registry (requires TFE_LICENSE env var)

## Architecture

This is a GCP Marketplace deployer for HashiCorp Terraform Enterprise using **External Services mode** (Cloud SQL PostgreSQL, Memorystore Redis, GCS bucket).

### Image Build Pipeline
```
images/tfe/Dockerfile          → gcr.io/.../terraform-enterprise:TAG
images/ubbagent/Dockerfile     → gcr.io/.../terraform-enterprise/ubbagent:TAG
deployer/Dockerfile            → gcr.io/.../terraform-enterprise/deployer:TAG
apptest/deployer/Dockerfile    → gcr.io/.../terraform-enterprise/tester:TAG
```

### Key Files
- `schema.yaml` - GCP Marketplace schema defining user inputs (hostname, license, TLS certs, database/redis/GCS config)
- `apptest/deployer/schema.yaml` - Test schema with default values for mpdev verify
- `manifest/manifests.yaml.template` - Kubernetes resources (Secrets, ConfigMaps, Deployment, Service)
- `manifest/application.yaml.template` - GCP Marketplace Application CRD
- `deployer/scripts/deploy_with_tests.sh` - Deployment script with wait timeout logic

### Shared Makefiles
- `../../shared/Makefile.common` - Docker build flags for GCP Marketplace compliance
- `../../shared/Makefile.product` - Generic deployer/tester build patterns

### Version Synchronization
All three files must have matching versions:
- `schema.yaml` → `publishedVersion: '1.22.1'`
- `apptest/deployer/schema.yaml` → `publishedVersion: '1.22.1'`
- `manifest/application.yaml.template` → `version: "1.22.1"`

Image tags use full semver (e.g., `1.22.1`) with an additional **minor version** alias (e.g., `1.22`).

## Infrastructure (Terraform)

Pre-provisioned via `terraform/` using HashiCorp's `terraform-google-terraform-enterprise-gke-hvd` module:
- Cloud SQL PostgreSQL (10.100.1.2:5432)
- Memorystore Redis (10.100.0.4)
- GCS bucket (poc-tfe-gcs-41981521)
- GKE cluster (tfe-gke-cluster)

**Terraform commands:**
```bash
cd terraform && terraform init && terraform apply
```

## TLS Certificates

Test certificates in `terraform/certs/`:
- `tfe.crt` - Certificate
- `tfe.key` - Private key
- `ca-bundle.pem` - CA bundle (same as cert for self-signed)

Values in schema files must be **base64-encoded**. The certificate and key must match (verify with modulus hash).

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
| `Invalid schema publishedVersion "1.22"; must be semver including patch version` | publishedVersion needs full semver | Use `1.22.1` not `1.22` in both schema.yaml files |
| `Application resource's spec.descriptor.version "X" does not match schema.yaml's publishedVersion "Y"` | Version mismatch between files | Ensure all 3 files have matching versions (see Version Synchronization) |
| `ImagePullBackOff` | Image tag doesn't exist in GCR | Run `make release` with matching TAG, ensure `publishedVersion` matches |
| `vault-manager crash loop` / `error running keymgmt get unseal` | Missing `ENC_PASSWORD` env var (or stale data) | Ensure `ENC_PASSWORD` is set in manifest (same value as `TFE_ENCRYPTION_PASSWORD`). If stale data: clean vault_* tables in PostgreSQL and flush Redis |
| `keymgmt invalid port after host` | DATABASE_URL has special chars (e.g., `/` in password) | Use URL-encoded password in DATABASE_URL. Add `databasePasswordEncoded` variable with `/` as `%2F` |
| `keymgmt message authentication failed` | Stale vault data encrypted with different ENC_PASSWORD | Truncate `vault.vault_kv_store` and `vault.vault_ha_locks` tables in PostgreSQL, flush Redis |
| `Startup probe timeout` | TFE takes too long to start | Increase `failureThreshold` in manifests.yaml.template |

**Pre-flight checklist before running mpdev verify:**
1. All 3 version files match: `schema.yaml`, `apptest/deployer/schema.yaml`, `manifest/application.yaml.template`
2. Images built with same TAG as `publishedVersion`
3. Previous test namespaces cleaned up: `kubectl delete ns apptest-*`
4. Vault data cleaned for fresh install (see below)

**Cleaning stale vault data (required for fresh mpdev verify runs):**
```bash
# Flush Redis
kubectl run redis-flush --rm -it --restart=Never --image=redis:7 -- \
  redis-cli -h 10.100.0.4 -a "<redis-password>" FLUSHALL

# Truncate vault tables in PostgreSQL (note: vault uses its own schema)
kubectl run psql-cleanup --rm -i --restart=Never --image=postgres:15 -- \
  psql "postgresql://tfe:<url-encoded-password>@10.100.1.2:5432/tfe?sslmode=require" <<EOF
TRUNCATE vault.vault_kv_store CASCADE;
TRUNCATE vault.vault_ha_locks CASCADE;
EOF
```

## GCP Marketplace Requirements

Images must be:
- Single architecture (`linux/amd64`)
- Docker V2 manifests (`--provenance=false --sbom=false`)
- Annotated with `com.googleapis.cloudmarketplace.product.service.name`
- Tagged with semantic minor version (e.g., `1.22` not `latest`)
