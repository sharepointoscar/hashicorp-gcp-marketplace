# Plan: Nomad Enterprise GCP Marketplace Kubernetes App

## Context

Add Nomad Enterprise as a new GCP Marketplace Click-to-Deploy Kubernetes App to the monorepo. Nomad is a workload orchestrator — architecturally most similar to Consul in this repo (Raft integrated storage, Serf gossip, multi-node StatefulSet). No official Helm chart exists, so we build custom manifests using `deployer_envsubst` (like Vault/Consul, NOT Helm like TFE).

**User decisions**:
- Server-only deployment (3-node StatefulSet control plane)
- Nomad Enterprise license available
- Version: `1.11.2-ent` — latest stable, Go 1.25.7, all known Nomad CVEs patched. Same Go version as 1.10.8-ent LTS so no CVE advantage to either. Dockerfile will patch OS-level CVEs (OpenSSL) like other products.

## Version Target

**`hashicorp/nomad:1.11.2-ent`** from Docker Hub (no registry auth needed, same as Vault).

Confirmed on releases.hashicorp.com:
- `nomad_1.11.2+ent` — released 2026-02-11, Go 1.25.7
- `nomad_1.10.8+ent` — released 2026-02-11, Go 1.25.7 (LTS, enterprise-only)
- Docker Hub tags: `hashicorp/nomad:1.11.2-ent` (64.9 MB, multi-arch amd64+arm64)

### CVE Status (as of 2026-02-24)

**Nomad-specific CVEs (all fixed in 1.11.2 and 1.10.8):**
| CVE | Severity | Description | Fixed In |
|-----|----------|-------------|----------|
| CVE-2025-4922 | HIGH (8.1) | ACL prefix-based policy lookup incorrect rule application | 1.10.2+ |
| CVE-2025-3744 | Medium | Enterprise Sentinel policy bypass via policy override | 1.10.1+ |
| CVE-2025-1296 | Medium | Workload identity token exposed in audit logs | 1.9.7+ |

**Go stdlib CVEs**: All fixed via Go 1.25.7 (CVE-2025-61732, CVE-2025-68121, CVE-2025-61730, CVE-2025-61726, CVE-2025-61728, CVE-2025-61729).

### Base Image (CONFIRMED)

`hashicorp/nomad:1.11.2-ent` is **BusyBox-based** (NOT Alpine, NOT UBI):
- BusyBox v1.36.0 (~3.85MB base layer)
- **No package manager** — no `apk`, `apt`, `yum`, `microdnf`
- **Runs as root** (uid=0, gid=0) — no `nomad` user exists
- Binary at `/bin/nomad` (142MB static binary)
- Includes `/docker-entrypoint.sh`

**Multi-stage build is REQUIRED** (not a fallback — it's the only option):
1. Extract `/bin/nomad` from official image (entrypoint not needed — StatefulSet `command` bypasses it)
2. Layer onto `alpine:3.20` where we can create a `nomad` user and patch CVEs

CVE mitigation strategy:
- `apk upgrade --no-cache` in Alpine layer to patch OS-level CVEs (OpenSSL, libcrypto3, libssl3)
- Scan with `gcloud artifacts docker images describe` during validation

## Files to Create

```
products/nomad/
├── Makefile                              # Based on Consul Makefile pattern
├── product.yaml                          # Product metadata
├── schema.yaml                           # User inputs
├── .gitignore                            # *.hclic, .build/, .terraform*
├── manifest/
│   ├── application.yaml.template         # GCP Application CRD
│   └── manifests.yaml.template           # K8s resources
├── deployer/
│   └── Dockerfile                        # deployer_envsubst based
├── apptest/deployer/
│   ├── Dockerfile                        # Tester image
│   ├── schema.yaml                       # Test defaults
│   └── manifest/
│       └── tester.yaml.template          # Verification tests
├── images/
│   ├── nomad/Dockerfile                  # App image (FROM hashicorp/nomad:1.11.2-ent)
│   └── ubbagent/Dockerfile              # Copy from products/vault/images/ubbagent/
└── README.md                             # Product documentation
```

## Step-by-Step Implementation

### Step 1: Directory scaffold + .gitignore

Create `products/nomad/` directory tree. Copy `.gitignore` pattern from Consul/Vault (ignore `*.hclic`, `.build/`, etc.).

### Step 2: Product metadata — `product.yaml`

Based on `products/consul/product.yaml`:
- `id: nomad`
- `version: 1.11.2`
- `partnerId: 0014M00001h317WQAQ` (same HashiCorp partner)
- `solutionId: nomad-enterprise`
- Ports: 4646 (HTTP/UI), 4647 (RPC), 4648 (Serf)

### Step 3: Makefile

Based on `products/consul/Makefile` pattern:
- `include ../../shared/Makefile.common` — reuse shared `DOCKER_BUILD_FLAGS`, colors, print helpers (DRY)
- `APP_ID := nomad`
- `VERSION := 1.11.2` (hardcoded like Consul, not derived from TAG/Dockerfile like Vault)
- Images: `nomad`, `ubbagent`, `deployer`, `tester` (4 images, no init image needed)
- `AR_REGISTRY ?= $(REGISTRY)` — no default, must be passed via env var
- `MP_SERVICE_NAME ?=` — **no default** (must be passed, fail-fast like Consul)
- `check-required-vars` guard — explicit check that `REGISTRY` and `MP_SERVICE_NAME` are non-empty before `app/build`
- Targets: `images/build`, `app/build`, `release`, `tags/minor`, `app/verify`, `app/install`, `clean`, `ns/clean`, `info`

### Step 4: Application image — `images/nomad/Dockerfile`

**Multi-stage build** (required — official image is BusyBox with no package manager):

```dockerfile
FROM hashicorp/nomad:1.11.2-ent AS official

FROM alpine:3.20

# Patch OS-level CVEs + install minimal deps
RUN apk upgrade --no-cache && \
    apk add --no-cache libcap su-exec dumb-init && \
    addgroup -g 1000 nomad && \
    adduser -u 100 -G nomad -s /bin/sh -D nomad && \
    mkdir -p /nomad/data /nomad/config && \
    chown -R nomad:nomad /nomad

COPY --from=official /bin/nomad /bin/nomad

# GCP Marketplace labels
LABEL com.google.cloud.marketplace.solution_id="nomad-enterprise" \
      com.google.cloud.marketplace.partner_id="0014M00001h317WQAQ"

USER nomad
EXPOSE 4646 4647 4648
```

**Notes**:
- No `ENTRYPOINT`/`CMD` — the StatefulSet `command` field handles invocation directly (`nomad agent -config=...`), matching the Consul pattern.
- No `docker-entrypoint.sh` copied — it's BusyBox-specific and unused when the StatefulSet command bypasses it.
- **User/group**: `nomad` (uid=100, gid=1000) — created in Dockerfile since official image has none.

### Step 5: UBB agent image — `images/ubbagent/Dockerfile`

**Copy from** `products/vault/images/ubbagent/Dockerfile` — identical build (Go 1.25, source build with CVE-2024-45337 fix). No changes needed.

### Step 6: Schema — `schema.yaml`

Based on `products/consul/schema.yaml` (multi-replica Raft pattern):

```yaml
x-google-marketplace:
  schemaVersion: v2
  applicationApiVersion: v1beta1
  publishedVersion: '1.11.2'
  partnerId: 0014M00001h317WQAQ
  solutionId: nomad-enterprise
  images:
    nomad:
      properties:
        imageNomad:
          type: FULL
    ubbagent:
      properties:
        imageUbbagent:
          type: FULL
  clusterConstraints:
    resources:
      - replicas: 3
        requests:
          cpu: 500m
          memory: 512Mi
        affinity:
          simpleNodeAffinity:
            type: REQUIRE_ONE_NODE_PER_REPLICA
    k8sVersion: ">=1.21.0"

properties:
  name / namespace / replicas (3, min 1, max 7) /
  datacenter (default: dc1) / region (default: global) /
  storageClass (SSD) / storageSize (default: 10Gi) /
  nomadLicense (MASKED_FIELD) /
  nomadServiceAccount (SERVICE_ACCOUNT with pod read perms) /
  reportingSecret (REPORTING_SECRET)

Note: `enableUI` removed — UI is always enabled (hardcoded in HCL config), matching Consul pattern.
```

### Step 7: Test schema — `apptest/deployer/schema.yaml`

Same structure as schema.yaml but with `default:` values for all properties:
- `replicas: 3` (minimum for Raft bootstrap)
- `nomadLicense: <dummy license string>` (from actual .hclic for testing)
- `storageClass: standard`

### Step 8: Manifest — `manifest/manifests.yaml.template`

Based on Consul's manifest pattern. Resources:

1. **ServiceAccount** — `$nomadServiceAccount`
2. **License Secret** — `$name-nomad-license` with `$nomadLicense`
3. **Config ConfigMap** — Nomad HCL:
   ```hcl
   data_dir   = "/nomad/data"
   datacenter = "$datacenter"
   region     = "$region"

   server {
     enabled          = true
     bootstrap_expect = $replicas
   }

   addresses {
     http = "0.0.0.0"
     rpc  = "0.0.0.0"
     serf = "0.0.0.0"
   }

   ports {
     http = 4646
     rpc  = 4647
     serf = 4648
   }

   server_join {
     retry_join = [
       "$name-nomad-0.$name-nomad-headless.$namespace.svc.cluster.local",
       "$name-nomad-1.$name-nomad-headless.$namespace.svc.cluster.local",
       "$name-nomad-2.$name-nomad-headless.$namespace.svc.cluster.local"
     ]
   }

   ui { enabled = true }

   telemetry {
     prometheus_metrics = true
     disable_hostname   = true
   }
   ```

4. **Headless Service** — `$name-nomad-headless` (clusterIP: None, publishNotReadyAddresses: true)
   - Ports: 4646 (http), 4647 (rpc), 4648 (serf TCP+UDP)

5. **API Service** — `$name-nomad-ui` (ClusterIP, port 4646)

6. **StatefulSet** — `$name-nomad`
   - `replicas: $replicas`
   - `podManagementPolicy: Parallel`
   - `persistentVolumeClaimRetentionPolicy: { whenDeleted: Delete, whenScaled: Delete }`
   - Security context: `runAsNonRoot: true, runAsUser: 100, runAsGroup: 1000, fsGroup: 1000`
   - Container `nomad`:
     - `command: ["nomad", "agent", "-config=/nomad/config/nomad.hcl"]`
     - Env: `NOMAD_LICENSE` from secret, `POD_IP` from fieldRef, `NOMAD_ADDR=http://127.0.0.1:4646`
     - Ports: 4646, 4647, 4648 (TCP+UDP)
     - Volume mounts: `/nomad/data` (PVC), `/nomad/config` (ConfigMap)
     - Resources: requests 500m/512Mi, limits 2000m/2Gi
     - Readiness: `httpGet /v1/status/leader port 4646` (initialDelay 30s) — matches Consul pattern, indicates cluster has a leader
     - Liveness: `exec nomad agent-info` (initialDelay 60s)
   - Container `ubbagent`: identical to Consul's UBB sidecar
   - Pod anti-affinity: prefer one replica per node (like Consul)
   - VolumeClaimTemplate: `data` 10Gi

7. **UBB ConfigMap** — metric `nomad_instance_time`, `serviceName: nomad.mp-hashicorp.appspot.com` (hardcoded, matching Consul pattern)

### Step 9: Application CRD — `manifest/application.yaml.template`

Standard GCP Application CRD:
- Descriptor: type "Nomad Enterprise", version, description, maintainers, links
- Component kinds: Secret, ConfigMap, Service, ServiceAccount, StatefulSet
- Notes: post-deploy instructions (accessing UI via port-forward, bootstrapping ACL)

### Step 10: Deployer Dockerfile — `deployer/Dockerfile`

Based on Vault's deployer (envsubst pattern):
```dockerfile
FROM gcr.io/cloud-marketplace-tools/k8s/deployer_envsubst
COPY manifest /data/manifest
COPY schema.yaml /data/schema.yaml
COPY apptest/deployer/schema.yaml /data-test/schema.yaml
COPY apptest/deployer/manifest /data-test/manifest
```

### Step 11: Tester Dockerfile — `apptest/deployer/Dockerfile`

```dockerfile
FROM gcr.io/cloud-marketplace-tools/k8s/deployer_envsubst
COPY schema.yaml /data-test/schema.yaml
COPY manifest /data-test/manifest
```

### Step 12: Tester Pod — `apptest/deployer/manifest/tester.yaml.template`

Pod with `activeDeadlineSeconds: 600` (matching Consul), uses `image: $imageNomad` for CLI access, inline shell script:
1. Wait for Nomad cluster via headless service (`$name-nomad-headless.$namespace.svc.cluster.local:4646`) — matches Consul pattern
2. Wait for leader election (`nomad operator raft list-peers | grep leader`)
3. Check `nomad server members` — verify all servers alive, count matches expected
4. Test variable operations: `nomad var put nomad/jobs/test key=value`, `nomad var get nomad/jobs/test`, cleanup
5. Verify Raft consensus (`nomad operator raft list-peers` — count leader+follower)
6. Health check endpoint (`curl /v1/status/leader`)
7. Verify Nomad Enterprise license is active (`nomad license get`)
8. Check UI accessibility (`curl /v1/agent/health`)

### Step 13: README.md

Product README with deployment instructions, prerequisites, architecture diagram, ports, debugging commands.

## Version Synchronization (must all match `1.11.2`)

- `schema.yaml` → `publishedVersion: '1.11.2'`
- `apptest/deployer/schema.yaml` → `publishedVersion: '1.11.2'`
- `manifest/application.yaml.template` → `version: '1.11.2'`
- `product.yaml` → `version: 1.11.2`
- `Makefile` → VERSION derived from TAG or Dockerfile

## Existing Files/Patterns Reused

| Asset | Source | Reuse |
|-------|--------|-------|
| UBB agent Dockerfile | `products/vault/images/ubbagent/Dockerfile` | Copy verbatim |
| UBB sidecar manifest | `products/consul/manifest/manifests.yaml.template` (lines 303-339) | Adapt metric name |
| Deployer Dockerfile | `products/vault/deployer/Dockerfile` | Copy pattern |
| Tester Dockerfile | `products/vault/apptest/deployer/Dockerfile` | Copy pattern |
| Makefile structure | `products/consul/Makefile` | Adapt for nomad images (includes shared Makefile.common, check-required-vars guard) |
| Schema structure | `products/consul/schema.yaml` | Adapt properties |
| StatefulSet pattern | `products/consul/manifest/manifests.yaml.template` | Adapt ports/config |
| Pod anti-affinity | `products/consul/manifest/manifests.yaml.template` (lines 341-350) | Copy verbatim |

## Artifact Registry Setup (Pre-requisite)

Before first build, create the Artifact Registry repo:
```bash
gcloud artifacts repositories create nomad-marketplace \
  --repository-format=docker \
  --location=us \
  --project=ibm-software-mp-project-test
```

## Validation & Testing

### Standard Workflow (single command)
```bash
cd products/nomad
REGISTRY=us-docker.pkg.dev/ibm-software-mp-project-test/nomad-marketplace \
  TAG=1.11.2 \
  MP_SERVICE_NAME=<service-name-from-portal> \
  ../../shared/scripts/validate-marketplace.sh nomad
```

This runs the full pipeline:
1. Prerequisites check + mpdev doctor
2. Build all images (`make release`)
3. Schema verification
4. mpdev install (test deployment)
5. mpdev verify (tester pod runs)
6. Vulnerability scan

### Manual Testing Steps
1. `make info` — verify all config values
2. `make app/build` — build images only
3. `make app/install` — deploy to test namespace
4. `kubectl get pods -n nomad-test` — verify 3/3 ready
5. `kubectl exec nomad-0 -- nomad server members` — verify cluster
6. `kubectl port-forward svc/nomad-ui 4646:4646` — access UI
7. `make app/verify` — run mpdev verify

### CVE Verification
```bash
gcloud artifacts docker images describe \
  us-docker.pkg.dev/ibm-software-mp-project-test/nomad-marketplace/nomad:1.11.2 \
  --show-package-vulnerability
```
Must show zero CRITICAL vulnerabilities.

### Production Push (after portal validation)
```bash
REGISTRY=us-docker.pkg.dev/ibm-software-mp-project/nomad-marketplace \
  TAG=1.11.2 \
  MP_SERVICE_NAME=<prod-service-name> \
  make release
```

## Unresolved Questions

1. **MP_SERVICE_NAME**: Env var at build time (Docker annotation). No default, fail-fast. Different per environment (test vs prod). **RESOLVED** — matches Consul pattern.
2. ~~**solutionId**~~: **RESOLVED** — Hardcoded `nomad-enterprise` in `schema.yaml`. Same across environments, matching Consul pattern (`consul`).
3. ~~**UBB serviceName**~~: **RESOLVED** — Hardcoded `nomad.mp-hashicorp.appspot.com` in UBB ConfigMap. Same across environments, matching Consul pattern (`consul.mp-hashicorp.appspot.com`).
4. ~~**Base image type**~~: **RESOLVED** — BusyBox-based. Multi-stage build onto Alpine confirmed as required approach.
5. ~~**Nomad user/group**~~: **RESOLVED** — Official image runs as root with no `nomad` user. Dockerfile creates `nomad` user (uid=100, gid=1000). securityContext: `runAsUser: 100, runAsGroup: 1000, fsGroup: 1000`.

## Refinements Applied (2026-02-24 review)

All refinements validated against `products/consul/` reference implementation:

| # | Refinement | Rationale |
|---|-----------|-----------|
| 1 | Removed `docker-entrypoint.sh` from Dockerfile | StatefulSet `command` bypasses entrypoint — dead code |
| 2 | Hardcoded `ui { enabled = true }`, removed `enableUI` from schema | Consul hardcodes UI; no customer disables it |
| 3 | Hardcoded `solutionId` and UBB `serviceName` | Consul/Vault hardcode these; not environment-specific |
| 5 | readinessProbe uses `/v1/status/leader` | Matches Consul; indicates cluster readiness |
| 6 | Makefile uses `include ../../shared/Makefile.common` | DRY — reuses shared build flags and helpers |
| 7 | Makefile adds `check-required-vars` guard | Explicit fail-fast on missing REGISTRY/MP_SERVICE_NAME |
| 8 | Tester connects to headless service | Matches Consul; direct pod access for reliability |
| 9 | Tester uses `$imageNomad` for CLI access | Matches Consul; nomad binary available in tester Pod |
