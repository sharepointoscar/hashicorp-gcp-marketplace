# HashiCorp Vault Enterprise - GCP Marketplace

This is the GCP Marketplace Click-to-Deploy package for **HashiCorp Vault Enterprise**
using **Raft integrated storage** on GKE. It is designed to be self-contained: no
external database is required.

## Architecture Overview

- **Type**: Kubernetes App (Click-to-Deploy via `mpdev`)
- **Storage**: Raft integrated storage with PVCs
- **License**: Vault Enterprise license injected via `VAULT_LICENSE` env var
- **Images**: Vault Enterprise base image from Docker Hub
- **Billing**: UBB agent sidecar for GCP Marketplace usage reporting

### Components

| Component | Purpose |
|-----------|---------|
| `vault` StatefulSet | Vault Enterprise servers (default 3 replicas) |
| `vault-init` | Init container for pre-flight checks |
| `ubbagent` | Usage-based billing sidecar |
| `deployer` | Marketplace deployer image |
| `tester` | Marketplace verification tests |

### Services

| Service | Type | Purpose |
|---------|------|---------|
| `$name-vault-internal` | Headless | Pod DNS + Raft communication |
| `$name-vault` | ClusterIP | Vault API (active node only) |
| `$name-vault-ui` | ClusterIP | Vault UI access |

## Prerequisites

- GKE cluster v1.21+
- `gcloud`, `kubectl`, `docker`
- `mpdev` (auto-wrapped by validation script if missing)
- Vault Enterprise license file (`.hclic`)
- Artifact Registry repository for images

## Environment Variables

```bash
export PROJECT_ID=<your-gcp-project>
export REGISTRY=us-docker.pkg.dev/$PROJECT_ID/vault-marketplace
export TAG=1.21.0
```

## Step-by-Step Deployment

### 1) Configure GCP and Docker

```bash
gcloud auth login
gcloud config set project $PROJECT_ID
gcloud auth configure-docker us-docker.pkg.dev
```

### 2) Add Your Vault Enterprise License

Place your `.hclic` file in this directory:

```bash
cp /path/to/vault.hclic products/vault/
```

The validation script automatically detects the license file and injects it for tests.

### 3) Build Images

```bash
cd products/vault
REGISTRY=$REGISTRY TAG=$TAG make app/build
```

### 4) Run Full Marketplace Validation (Recommended)

```bash
REGISTRY=$REGISTRY TAG=$TAG \
  ../../shared/scripts/validate-marketplace.sh vault
```

Optional:

```bash
REGISTRY=$REGISTRY TAG=$TAG \
  ../../shared/scripts/validate-marketplace.sh vault --keep-deployment
```

### 5) (Optional) Direct mpdev Install/Verify

```bash
REGISTRY=$REGISTRY TAG=$TAG make app/install
REGISTRY=$REGISTRY TAG=$TAG make app/verify
```

## Post-Deploy Steps (Init + Unseal)

Vault deploys **sealed**. Initialize and unseal before use.

```bash
# Initialize
kubectl exec -it $name-vault-0 -n $namespace -- vault operator init

# Unseal (run 3 times with different keys)
kubectl exec -it $name-vault-0 -n $namespace -- vault operator unseal
```

### Access the UI

```bash
kubectl port-forward svc/$name-vault-ui -n $namespace 8200:8200
```

Open: `https://localhost:8200`

## Resource Defaults (Raft Guide Baseline)

Vault server pods default to:

- **Requests**: `cpu: 2000m`, `memory: 8Gi`
- **Limits**: `cpu: 2000m`, `memory: 16Gi`

These align with the Raft deployment guide and can be overridden via schema inputs:

- `vaultResourcesRequestsCpu`
- `vaultResourcesRequestsMemory`
- `vaultResourcesLimitsCpu`
- `vaultResourcesLimitsMemory`

## Schema Properties (Key)

| Property | Default | Description |
|---------|---------|-------------|
| `replicas` | 3 | Vault server replicas |
| `storageClass` | SSD | Storage class for PVCs |
| `storageSize` | 10Gi | PVC size per replica |
| `vaultLicense` | required | Enterprise license (masked) |
| `reportingSecret` | required | Marketplace billing secret |
| `vaultResourcesRequestsCpu` | 2000m | CPU request per pod |
| `vaultResourcesRequestsMemory` | 8Gi | Memory request per pod |
| `vaultResourcesLimitsCpu` | 2000m | CPU limit per pod |
| `vaultResourcesLimitsMemory` | 16Gi | Memory limit per pod |

## Troubleshooting

### Common Issues

| Error | Cause | Fix |
|-------|-------|-----|
| `ImagePullBackOff` | Wrong tag or registry config | Verify `TAG`, run `gcloud auth configure-docker us-docker.pkg.dev` |
| `license is not valid` | Missing/expired license | Verify `vaultLicense` secret |
| `Raft timeout` | Pod communication issues | Check headless service and networking |
| `vault status` exit 2 | Vault is sealed | Unseal with `vault operator unseal` |

### Verify Enterprise

```bash
kubectl logs -n $namespace $name-vault-0 -c vault | grep "Enterprise"
```

## Cleanup

```bash
REGISTRY=$REGISTRY TAG=$TAG \
  ../../shared/scripts/validate-marketplace.sh vault --cleanup
```

## Version Synchronization Checklist

Keep these in sync when bumping versions:

- `schema.yaml` (`publishedVersion`)
- `apptest/deployer/schema.yaml` (`publishedVersion`)
- `manifest/application.yaml.template` (`version`)
- `product.yaml` (`version`)
- `Makefile` (`VERSION`, `VAULT_VERSION`)
