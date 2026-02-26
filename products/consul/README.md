# HashiCorp Consul Enterprise - GCP Marketplace

This is the GCP Marketplace Click-to-Deploy package for **HashiCorp Consul Enterprise**
using **Raft integrated storage** on GKE. It is fully self-contained: no external
database or storage backend is required.

## Architecture Overview

- **Type**: Kubernetes App (Click-to-Deploy via `mpdev`)
- **Storage**: Raft integrated storage with PersistentVolumeClaims
- **License**: Consul Enterprise license injected via `CONSUL_LICENSE` env var
- **Images**: Consul Enterprise base image from Docker Hub (multi-stage build for CVE remediation)
- **Billing**: UBB agent sidecar for GCP Marketplace usage reporting
- **Replicas**: 3 by default (odd number required for Raft consensus)

### Components

| Component | Purpose |
|-----------|---------|
| `consul` StatefulSet | Consul Enterprise server cluster (3 replicas default) |
| `ubbagent` sidecar | Usage-based billing agent for GCP Marketplace |
| `deployer` | Marketplace deployer image (envsubst-based) |
| `tester` | Marketplace verification tests (7 tests) |

### Services

| Service | Type | Purpose |
|---------|------|---------|
| `$name-consul-headless` | Headless | StatefulSet DNS discovery for Raft `retry_join` |
| `$name-consul-ui` | ClusterIP | Consul HTTP API and web UI |
| `$name-consul-dns` | ClusterIP | DNS queries (TCP/UDP port 8600) |

### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8500 | TCP | HTTP API and UI |
| 8502 | TCP | gRPC API |
| 8300 | TCP | Server RPC |
| 8301 | TCP/UDP | Serf LAN gossip |
| 8302 | TCP/UDP | Serf WAN gossip |
| 8600 | TCP/UDP | DNS interface |

Note: HTTPS (8501) and gRPC TLS (8503) are disabled in the default configuration (`-1` in consul.hcl).

### Consul Configuration Highlights

The ConfigMap (`$name-consul-config`) generates `consul.hcl` with:

- `server = true` and `bootstrap_expect` matching the replica count
- Raft integrated storage at `/consul/data`
- Connect (service mesh) enabled
- Prometheus telemetry with 30-second retention
- `raft_multiplier = 1` for production performance
- `retry_join` pointing to the first three StatefulSet pods via headless service DNS

## Prerequisites

- GKE cluster v1.21+ (Google verification runs GKE 1.33 and 1.35)
- `gcloud`, `kubectl`, `docker`
- `mpdev` (auto-wrapped by validation script if missing)
- Consul Enterprise license file (`.hclic`) placed in this directory
- Artifact Registry repository for images (e.g., `us-docker.pkg.dev/$PROJECT_ID/consul-marketplace`)
- HashiCorp container registry login (required for pulling base Consul Enterprise images)

## Directory Structure

```
products/consul/
├── CLAUDE.md                                  # Product-specific guidance for Claude Code
├── Makefile                                   # Build, release, and validation targets
├── product.yaml                               # Product metadata (id, version, partnerId)
├── schema.yaml                                # GCP Marketplace schema (user inputs)
├── .gitignore                                 # Ignores *.hclic and .build/
├── architecture.excalidraw                    # Architecture diagram source
├── deployer/
│   └── Dockerfile                             # Deployer image (envsubst base)
├── manifest/
│   ├── application.yaml.template              # GCP Marketplace Application CRD
│   └── manifests.yaml.template                # Kubernetes resources (ConfigMap, Services, StatefulSet)
├── apptest/
│   └── deployer/
│       ├── Dockerfile                         # Tester image
│       ├── schema.yaml                        # Test schema with default values
│       └── manifest/
│           └── tester.yaml.template           # Tester Pod (7 verification tests)
└── images/
    ├── consul/
    │   └── Dockerfile                         # Multi-stage: 1.22.4-ubi binary on 1.22.3 Alpine base
    └── ubbagent/
        └── Dockerfile                         # UBB agent built from source with Go 1.25
```

## Build and Validate

### Environment Variables

```bash
export PROJECT_ID=<your-gcp-project>
export REGISTRY=us-docker.pkg.dev/$PROJECT_ID/consul-marketplace
export TAG=1.21.7
export MP_SERVICE_NAME=services/ibmconsulselfmanaged.endpoints.ibm-software-mp-project.cloud.goog
```

### 1) Configure GCP and Docker

```bash
gcloud auth login
gcloud config set project $PROJECT_ID
gcloud auth configure-docker us-docker.pkg.dev
```

### 2) Add Your Consul Enterprise License

Place your `.hclic` file in this directory:

```bash
cp /path/to/consul.hclic products/consul/
```

The Makefile auto-detects `.hclic` files for registry login and mpdev verify/install.

### 3) Log into HashiCorp Container Registry

```bash
cd products/consul
make registry/login
```

This reads the license from the `.hclic` file and authenticates to `images.releases.hashicorp.com`.

### 4) Run Full Marketplace Validation (Recommended)

```bash
REGISTRY=$REGISTRY TAG=$TAG MP_SERVICE_NAME=$MP_SERVICE_NAME \
  ../../shared/scripts/validate-marketplace.sh consul
```

This runs the complete pipeline: prerequisites check, image builds, schema verification, mpdev install, mpdev verify, and vulnerability scan.

Optional flags:

```bash
# Keep deployment for inspection
../../shared/scripts/validate-marketplace.sh consul --keep-deployment

# Clean up test namespaces and orphaned PVs
../../shared/scripts/validate-marketplace.sh consul --cleanup
```

### 5) Individual Build Targets

```bash
# Build all images (consul, ubbagent, deployer, tester)
REGISTRY=$REGISTRY TAG=$TAG MP_SERVICE_NAME=$MP_SERVICE_NAME make app/build

# Full release: clean, build, push, add minor version tags
REGISTRY=$REGISTRY TAG=$TAG MP_SERVICE_NAME=$MP_SERVICE_NAME make release

# Add minor version tags only (e.g., 1.21 from 1.21.7)
REGISTRY=$REGISTRY TAG=$TAG MP_SERVICE_NAME=$MP_SERVICE_NAME make tags/minor

# Direct mpdev verify (reads license from *.hclic)
REGISTRY=$REGISTRY TAG=$TAG MP_SERVICE_NAME=$MP_SERVICE_NAME make app/verify

# Direct mpdev install
REGISTRY=$REGISTRY TAG=$TAG MP_SERVICE_NAME=$MP_SERVICE_NAME make app/install

# Display build configuration
make info
```

### Image Build Pipeline

The Makefile builds and pushes four images:

```
images/consul/Dockerfile      -> REGISTRY/consul:TAG        (multi-stage: 1.22.4-ubi binary on 1.22.3 Alpine)
images/ubbagent/Dockerfile    -> REGISTRY/ubbagent:TAG      (built from source with Go 1.25)
deployer/Dockerfile           -> REGISTRY/deployer:TAG       (envsubst deployer)
apptest/deployer/Dockerfile   -> REGISTRY/tester:TAG         (mpdev verification tests)
```

All images are built for `linux/amd64` with `--provenance=false --sbom=false` and annotated with the `MP_SERVICE_NAME`.

### Note on Consul Upstream Version

The Makefile defines two version variables:

- `VERSION` (`1.21.7`): The marketplace image tag and published version
- `CONSUL_VERSION` (`1.22.4`): The upstream HashiCorp Consul binary version extracted during the multi-stage build

These are intentionally different. The Consul image Dockerfile extracts the binary from `hashicorp/consul-enterprise:1.22.4-ent-ubi` and layers it onto the `hashicorp/consul-enterprise:1.22.3-ent` Alpine base. This is a temporary workaround because HashiCorp pulled the standard Alpine image for 1.22.4-ent from Docker Hub.

## Schema Properties

All user-configurable properties from `schema.yaml`:

| Property | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `name` | string | -- | Yes | Application name (GCP Marketplace NAME type) |
| `namespace` | string | -- | Yes | Kubernetes namespace (GCP Marketplace NAMESPACE type) |
| `replicas` | integer | `3` | Yes | Number of Consul server replicas (must be odd, range 1-7) |
| `datacenter` | string | `dc1` | Yes | Name of the Consul datacenter |
| `enableUI` | boolean | `true` | No | Enable the Consul web UI |
| `enableConnect` | boolean | `true` | No | Enable Consul Connect service mesh |
| `storageClass` | string | SSD | Yes | Kubernetes storage class for PVCs (GCP Marketplace STORAGE_CLASS type) |
| `storageSize` | string | `10Gi` | Yes | Size of persistent volume per Consul server |
| `consulLicense` | string | -- | No | Consul Enterprise license key (GCP Marketplace MASKED_FIELD type) |
| `consulServiceAccount` | string | -- | Yes | Service account for Consul pods (ClusterRole with pods get/list/watch) |
| `reportingSecret` | string | -- | Yes | GCP Marketplace billing reporting secret |

### Cluster Constraints

Defined in the `x-google-marketplace.clusterConstraints` section of `schema.yaml`:

- **Replicas**: 3
- **Requests per replica**: `cpu: 500m`, `memory: 512Mi`
- **Node affinity**: `REQUIRE_ONE_NODE_PER_REPLICA`
- **Minimum Kubernetes version**: `>=1.21.0`

### Resource Defaults (StatefulSet)

Consul server container defaults (hardcoded in `manifests.yaml.template`):

- **Requests**: `cpu: 500m`, `memory: 512Mi`
- **Limits**: `cpu: 2000m`, `memory: 2Gi`

## Post-Deploy: Accessing Consul

### Access the UI

```bash
kubectl port-forward svc/$name-consul-ui -n $namespace 8500:8500
```

Open: `http://localhost:8500/ui`

### Verify the Cluster

```bash
kubectl exec -n $namespace $name-consul-0 -- consul members
```

### Key/Value Store

```bash
# Write
kubectl exec -n $namespace $name-consul-0 -- consul kv put hello world

# Read
kubectl exec -n $namespace $name-consul-0 -- consul kv get hello
```

## Verification Tests

The tester Pod (`apptest/deployer/manifest/tester.yaml.template`) runs 7 tests with a 600-second deadline:

1. **Cluster Availability** -- waits for Consul cluster to report alive members
2. **Leader Election** -- waits for Raft leader to be elected
3. **Cluster Members** -- verifies at least 1 active member
4. **Key/Value Store** -- writes, reads, and deletes a test key
5. **Raft Consensus** -- verifies Raft voters via `consul operator raft list-peers`
6. **Health Check** -- queries the `/v1/status/leader` HTTP endpoint
7. **Service Registration** -- registers and deregisters a test service via catalog

## Version Synchronization

These files must have matching versions when bumping the marketplace image tag:

| File | Field | Current Value |
|------|-------|---------------|
| `schema.yaml` | `publishedVersion` | `1.21.7` |
| `apptest/deployer/schema.yaml` | `publishedVersion` | `1.21.7` |
| `manifest/application.yaml.template` | `version` (in `spec.descriptor`) | `1.21.7` |
| `Makefile` | `VERSION` | `1.21.7` |

Additionally, `product.yaml` contains its own `version` field (currently `1.21.0`) and a `metadata.version` field (currently `1.21.0`).

The `CONSUL_VERSION` in the Makefile (`1.22.4`) tracks the upstream HashiCorp binary version and is independent of the marketplace tag.

## Debugging

```bash
# Check pod status
kubectl get pods -n $namespace

# Check Consul server logs
kubectl logs -n $namespace $name-consul-0 -c consul

# Check UBB agent logs
kubectl logs -n $namespace $name-consul-0 -c ubbagent

# Check cluster members
kubectl exec -n $namespace $name-consul-0 -- consul members

# Check Raft peers
kubectl exec -n $namespace $name-consul-0 -- consul operator raft list-peers

# Check leader
kubectl exec -n $namespace $name-consul-0 -- consul operator raft list-peers | grep leader

# Test KV store
kubectl exec -n $namespace $name-consul-0 -- consul kv put test value
kubectl exec -n $namespace $name-consul-0 -- consul kv get test

# Check Application CRD status
kubectl get applications -n $namespace

# Port-forward the UI
kubectl port-forward -n $namespace svc/$name-consul-ui 8500:8500
```

### Common Issues

| Error | Cause | Fix |
|-------|-------|-----|
| `ImagePullBackOff` | Missing registry auth or wrong tag | Run `make registry/login` and verify TAG matches `publishedVersion` |
| `No cluster leader` | Insufficient replicas or network issues | Ensure replicas is an odd number (1, 3, 5, 7) |
| `Raft timeout` | Pod communication issues | Check headless service and pod anti-affinity |
| `License invalid` | Missing or expired license | Update the `.hclic` file or check the `$name-consul-license` secret |
| `No .hclic file found` | License file missing from product directory | Place your Consul Enterprise license (`.hclic`) in `products/consul/` |
| `MP_SERVICE_NAME is required` | Build failed due to missing annotation | Export `MP_SERVICE_NAME` before running `make` |

## Cleanup

```bash
# Clean local build artifacts
make clean

# Clean Artifact Registry images for current version
REGISTRY=$REGISTRY make ar/clean

# Clean ALL Artifact Registry images
REGISTRY=$REGISTRY make ar/clean-all

# Clean up test namespaces via shared script
REGISTRY=$REGISTRY TAG=$TAG ../../shared/scripts/validate-marketplace.sh consul --cleanup
```
