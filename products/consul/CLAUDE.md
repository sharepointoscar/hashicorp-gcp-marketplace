# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Consul GCP Marketplace product.

## Build Commands

**Prerequisites:**
```bash
# Authenticate to GCP
gcloud auth login && gcloud auth configure-docker

# Place your Consul Enterprise license file in this directory
cp /path/to/your/consul-license.hclic .

# Login to HashiCorp registry (reads from .hclic file automatically)
make registry/login
```

**Standard Validation Workflow (USE THIS):**
```bash
# Full validation pipeline - builds, schema check, install, verify, vuln scan
# The shared script auto-detects the *.hclic file and includes license in parameters
REGISTRY=gcr.io/$PROJECT_ID TAG=1.22.2 \
  ../../shared/scripts/validate-marketplace.sh consul

# With --keep-deployment to inspect after validation
REGISTRY=gcr.io/$PROJECT_ID TAG=1.22.2 \
  ../../shared/scripts/validate-marketplace.sh consul --keep-deployment
```

**Individual targets (for quick iteration):**
```bash
# Build only
REGISTRY=gcr.io/$PROJECT_ID TAG=1.22.2 make app/build

# Direct mpdev verify (reads license from *.hclic)
REGISTRY=gcr.io/$PROJECT_ID TAG=1.22.2 make app/verify

# Direct mpdev install (reads license from *.hclic)
REGISTRY=gcr.io/$PROJECT_ID TAG=1.22.2 make app/install
```

**Other targets:**
- `make gcr/clean` - Delete all images from GCR
- `make gcr/tag-minor` - Add minor version tags (e.g., 1.20 from 1.22.2)
- `make clean` - Clean local build artifacts
- `make registry/login` - Login to HashiCorp registry (reads from *.hclic file)
- `make info` - Display build configuration

## Architecture

This is a GCP Marketplace Click-to-Deploy product for HashiCorp Consul Enterprise using **Raft Integrated Storage** (no external infrastructure required).

### Temporary: Consul 1.22.4 Binary from UBI Image (CVE Fix)

The standard Alpine image for `hashicorp/consul-enterprise:1.22.4-ent` was pulled by HashiCorp from Docker Hub and is unavailable. Only the UBI (Red Hat) variant `1.22.4-ent-ubi` exists. To fix CVE-2025-68121 (Go stdlib < 1.25.7), the Dockerfile uses a multi-stage build:

1. **Stage 1**: Extracts the consul binary (compiled with Go 1.25.7) from `hashicorp/consul-enterprise:1.22.4-ent-ubi`
2. **Stage 2**: Uses `hashicorp/consul-enterprise:1.22.3-ent` (Alpine) as the base for filesystem, users, and OS packages
3. Applies `apk upgrade openssl libcrypto3 libssl3` to fix CVE-2025-15467 (OpenSSL < 3.5.5)
4. Copies the 1.22.4 consul binary over the 1.22.3 binary

**This is temporary.** When HashiCorp publishes `1.22.5-ent` (or re-publishes `1.22.4-ent`) as a standard Alpine image, revert the Dockerfile to use the official image directly.

### Image Build Pipeline
```
images/consul/Dockerfile      → REGISTRY/consul:TAG        (multi-stage: 1.22.4-ubi binary on 1.22.3 Alpine)
images/ubbagent/Dockerfile    → REGISTRY/consul/ubbagent:TAG (built from source with Go 1.25)
deployer/Dockerfile           → REGISTRY/consul/deployer:TAG
apptest/deployer/Dockerfile   → REGISTRY/consul/tester:TAG
```

### Key Files
- `schema.yaml` - GCP Marketplace schema defining user inputs
- `apptest/deployer/schema.yaml` - Test schema with default values for mpdev verify
- `manifest/manifests.yaml.template` - Kubernetes resources (ConfigMap, Services, StatefulSet)
- `manifest/application.yaml.template` - GCP Marketplace Application CRD
- `product.yaml` - Product metadata

### Version Synchronization
All three files must have matching versions (marketplace image tag):
- `schema.yaml` → `publishedVersion: '1.21.7'`
- `apptest/deployer/schema.yaml` → `publishedVersion: '1.21.7'`
- `manifest/application.yaml.template` → `version: "1.21.7"`

Note: `CONSUL_VERSION` in the Makefile (currently `1.22.4`) is the upstream HashiCorp binary version, NOT the marketplace tag. These are intentionally different due to the multi-stage build approach.

## Consul Configuration

### Ports
| Port | Protocol | Purpose |
|------|----------|---------|
| 8500 | TCP | HTTP API and UI |
| 8501 | TCP | HTTPS API |
| 8502 | TCP | gRPC API |
| 8600 | TCP/UDP | DNS interface |
| 8300 | TCP | Server RPC |
| 8301 | TCP/UDP | Serf LAN gossip |
| 8302 | TCP/UDP | Serf WAN gossip |

### Services
| Service | Type | Purpose |
|---------|------|---------|
| `$name-consul-headless` | Headless | StatefulSet DNS discovery |
| `$name-consul-ui` | ClusterIP | UI and API access (use port-forward) |
| `$name-consul-dns` | ClusterIP | DNS queries |

### Storage
- Uses Raft integrated storage with PersistentVolumeClaims
- Default storage size: 10Gi per replica
- Recommended: SSD storage class for performance

## Debugging

```bash
# Check pod status
kubectl get pods -n <namespace>

# Check Consul logs
kubectl logs -n <namespace> <pod-name> -c consul

# Check cluster members
kubectl exec -n <namespace> $name-consul-0 -- consul members

# Check Raft peers
kubectl exec -n <namespace> $name-consul-0 -- consul operator raft list-peers

# Check leader status
kubectl exec -n <namespace> $name-consul-0 -- consul operator raft list-peers | grep leader

# Test KV store
kubectl exec -n <namespace> $name-consul-0 -- consul kv put test value
kubectl exec -n <namespace> $name-consul-0 -- consul kv get test

# Access UI (port-forward)
kubectl port-forward -n <namespace> svc/$name-consul-ui 8500:8500
```

## Common Issues

| Error | Cause | Fix |
|-------|-------|-----|
| `ImagePullBackOff` | Missing registry auth or wrong tag | Run `make registry/login` (ensure *.hclic file exists) and verify TAG matches publishedVersion |
| `No cluster leader` | Insufficient replicas or network issues | Ensure replicas is odd number (1, 3, 5, 7) |
| `Raft timeout` | Pod communication issues | Check headless service and pod anti-affinity |
| `License invalid` | Missing or expired license | Update the *.hclic license file or check the secret |
| `No .hclic file found` | License file missing | Place your Consul Enterprise license (*.hclic) in the product directory |
| CVE-2025-68121 (Go stdlib) | consul binary compiled with Go < 1.25.7 | Use multi-stage build to extract binary from 1.22.4-ent-ubi (see Architecture section) |
| CVE-2025-15467 (OpenSSL) | Alpine OpenSSL < 3.5.5 | Add `apk upgrade openssl libcrypto3 libssl3` in Dockerfile |
| CVE-2025-68121 (ubbagent) | ubbagent built with Go < 1.24.13 | Build from source with `golang:1.25-alpine` (see `images/ubbagent/Dockerfile`) |

## Enterprise License

**Build-time (registry auth):**
- Place your `*.hclic` license file in the `products/consul/` directory
- The Makefile auto-detects it for `make registry/login`

**Runtime (deployment):**
1. `schema.yaml` → `consulLicense` property (masked field in GCP Marketplace UI)
2. Secret: `$name-consul-license`
3. Environment variable: `CONSUL_LICENSE` in StatefulSet

## Comparison with Other Products

| Aspect | Consul | Vault | TFE |
|--------|--------|-------|-----|
| Storage | Raft (PVC) | Raft (PVC) | External (Cloud SQL, Redis) |
| External Infra | None | None | Required |
| Main Port | 8500 | 8200 | 443 |
| Replicas | 3 (odd required) | 3 (odd required) | 1+ |
| License | Enterprise required | Enterprise required | Enterprise required |
| Registry Auth | Required | Not required | Required |
