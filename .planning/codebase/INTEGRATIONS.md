# External Integrations

**Analysis Date:** 2025-02-24

## APIs & External Services

**HashiCorp Registries:**
- **images.releases.hashicorp.com** - Private image registry for TFE and Consul Enterprise
  - Auth: via `TFE_LICENSE` env var or Docker credentials file
  - Used by: `products/terraform-enterprise/`, `products/consul/`
  - Client: Docker CLI `docker login`

- **Docker Hub (hashicorp/)** - Public HashiCorp product images
  - Products: Vault Enterprise images (public, no auth required)
  - Used by: `products/vault/`

**GCP Cloud Marketplace:**
- **GCP Marketplace Producer Portal** - Listing and deployment management
  - Used for: Publishing product metadata, managing versions, tracking deployments
  - Metadata files: `schema.yaml`, `product.yaml`, `metadata.yaml` (Boundary)

**Google Cloud Platform (GCP) Services:**

- **Cloud Marketplace Deployer (mpdev)** - Click-to-Deploy orchestration
  - CLI tool for testing marketplace deployments (`./shared/scripts/validate-marketplace.sh`)
  - Validates app installation, verifies tester success, manages test deployments

- **Google Artifact Registry** - Container image hosting
  - Endpoint: `us-docker.pkg.dev/$PROJECT_ID/[product]-marketplace/`
  - Auth: gcloud CLI (`gcloud auth configure-docker us-docker.pkg.dev`)
  - Used by: All Kubernetes products (Vault, Consul, TFE, Terraform Cloud Agent)

- **Google Compute Engine API** - VM infrastructure
  - Used by: Boundary (Terraform modules create VMs, load balancers, firewall rules)
  - Endpoints managed via: `google` and `google-beta` Terraform providers

- **Google Cloud SQL** - PostgreSQL databases
  - Used by:
    - TFE: Embedded PostgreSQL in pod (self-contained) OR external Cloud SQL
    - Boundary: Cloud SQL PostgreSQL for state and configuration
  - Terraform modules: `google_sql_database_instance` resource
  - Connection: Private service access (VPC peering)
  - Client: JDBC (Java) / PostgreSQL CLI tools
  - Auth: Service account with Cloud SQL Client role

- **Google Memorystore for Redis** - In-memory data store
  - Used by: TFE (optional, for caching and session management)
  - Terraform modules: `google_redis_instance` resource
  - Connection: Private service access
  - Client: Standard Redis protocol
  - Auth: Service account with Memorystore Client role

- **Google Cloud Storage (GCS)** - Object storage
  - Used by:
    - TFE: Embedded MinIO in pod (self-contained) OR GCS bucket for artifacts
    - Boundary: GCS bucket for Session Recording (BSR) and backups
  - Terraform modules: `google_storage_bucket` resource
  - Client: `gsutil` CLI or SDK
  - Auth: Service account with Storage Object Admin role

- **Google Cloud KMS** - Key management
  - Used by: Boundary (encryption keys for root, worker, recovery, and BSR)
  - Resources: `google_kms_key_ring`, `google_kms_crypto_key` (Terraform)
  - Client: gcloud CLI or service account impersonation
  - Auth: Service account with Cloud KMS Crypto Operator role

- **Google Secret Manager** - Credential and secret storage
  - Used by:
    - Boundary: License storage (retrieved at deployment time)
    - TFE: Optional for sensitive configuration
  - Terraform modules: `google_secret_manager_secret`, `google_secret_manager_secret_version`
  - Client: gcloud CLI or SDK
  - Auth: Service account with Secret Manager Secret Accessor role

- **Google Cloud DNS** - DNS management
  - Used by: Boundary (A records for controller/worker load balancers)
  - Terraform modules: `google_dns_record_set` resource
  - Auth: Service account with DNS Admin role

- **Google Cloud Load Balancer** - Traffic distribution
  - Used by:
    - Boundary: TCP/SSL load balancers for controllers and workers
    - TFE: Internal load balancer (optional)
  - Terraform modules: `google_compute_backend_service`, `google_compute_forwarding_rule`
  - Auth: Service account with Compute Load Balancer Admin role

- **Google Cloud IAM** - Identity and access management
  - Used by: All products for service account creation and role binding
  - Terraform modules: `google_service_account`, `google_project_iam_member`

- **Google Cloud VPC** - Virtual networking
  - Used by: All products for network isolation
  - Terraform modules: `google_compute_network`, `google_compute_subnetwork`

- **Google Cloud Firewall** - Network access control
  - Used by: Boundary (ingress/egress rules for controller/worker traffic)
  - Terraform modules: `google_compute_firewall` resource

- **Google Container Registry (GCR)** - Legacy image registry (transitioning to Artifact Registry)
  - Legacy support: Some scripts and configurations reference `gcr.io/`
  - Direction: New builds use Artifact Registry exclusively

## Data Storage

**Databases:**

- **PostgreSQL (Cloud SQL or embedded)**
  - TFE: Embedded PostgreSQL in pod via init container (self-contained v1.1.3) OR external Cloud SQL
    - Connection: `postgresql://user:password@host:5432/terraform-enterprise?sslmode=require`
    - Credentials: Embedded in `_helpers.tpl` secrets
  - Boundary: Cloud SQL PostgreSQL
    - Connection: Private service access (internal IP)
    - Database: `boundary`
    - User: Service account-managed
  - Consul: Uses Raft integrated storage (no external DB)
  - Vault: Uses Raft integrated storage (file backend, no external DB)

**File Storage:**

- **GCS buckets** - Object storage
  - TFE: MinIO pod (S3-compatible in-cluster alternative)
  - Boundary: Session Recording (BSR) and backups

- **Local filesystem only** - Vault and Consul
  - Vault: File backend using PersistentVolumeClaim
  - Consul: Raft state using PersistentVolumeClaim

**Caching:**

- **Memorystore Redis** - Optional caching layer
  - TFE: Redis for session management and caching
  - Embedded Redis pod: MinIO pod can use in-cluster Redis for local caching

## Authentication & Identity

**Auth Provider:**

- **GCP Service Accounts** - Workload Identity
  - Boundary: Service account for Compute Engine API calls
  - TFE: Service account for Cloud SQL, GCS operations
  - Implementation: GCP Workload Identity (pod -> service account binding)
  - Environment: `GOOGLE_APPLICATION_CREDENTIALS` (default) or service account email

- **Custom (HashiCorp-managed)**
  - TFE: Local authentication via Terraform state
  - Vault: Unsealing via Shamir secrets or auto-unsealing via Cloud KMS
  - Boundary: Local authentication and database-backed authorization
  - Consul: Gossip encryption (shared secret) and TLS mutual auth

**License Management:**

- **GCP Secret Manager** - License storage (retrieved at deployment)
- **gcloud CLI** - Injected as environment variables at pod startup
- **Files** - Enterprise license files (*.hclic) stored locally and injected into Kubernetes secrets

## Monitoring & Observability

**Error Tracking:**

- Not detected - No integration with Sentry, Rollbar, or similar services
- Fallback: Kubernetes pod logs (`kubectl logs`) and GCP Cloud Logging

**Logs:**

- **Kubernetes pod logs** - Native container logging
  - Collection: kubectl logs or `kubectl attach` for live streaming
  - Redirection: Pod stdout/stderr
  - Approach: Application logs written to stdout (standard container practice)

- **GCP Cloud Logging** - Optional centralized logging (not enforced)
  - Integration: Via GKE-managed logging agents (optional)
  - Products: Can output to Cloud Logging if configured

- **Application-specific logs:**
  - Vault: Logs via Vault CLI
  - Consul: Logs via Consul CLI
  - TFE: Logs written to container stdout and file backend
  - Boundary: Systemd journalctl (for VM-based deployment)

## CI/CD & Deployment

**Hosting:**

- **GCP Cloud Marketplace** - Primary distribution and deployment platform
- **GKE (Google Kubernetes Engine)** - Deployment target for K8s products
- **Compute Engine** - Deployment target for Boundary VM solution

**CI Pipeline:**

- **GCP Cloud Marketplace validation** - Not a traditional CI/CD pipeline
  - Script: `./shared/scripts/validate-marketplace.sh`
  - Workflow:
    1. Prerequisites check (mpdev, docker, gcloud, kubectl)
    2. Build all images (make release)
    3. Schema validation
    4. mpdev install - Deploy test application
    5. mpdev verify - Run tester pod, verify exit code 0
    6. Vulnerability scan check
    7. Cleanup (namespace, PVs)
  - No automatic triggers (manual for now)

- **Packer CI (Boundary only)**
  - Workflow: `packer init` → `packer validate` → `packer build`
  - Output: Custom VM image pre-baked with Boundary binary (no internet required at deployment)

- **Terraform workflows (Infrastructure)**
  - `terraform init` → `terraform validate` → `terraform plan` → `terraform apply`
  - Pre-infrastructure: Cloud SQL, Redis, GCS for TFE (self-contained v1.1.3 removed these requirements)

## Environment Configuration

**Required env vars (build):**

- `REGISTRY` - Artifact Registry path (e.g., `us-docker.pkg.dev/$PROJECT_ID/vault-marketplace`)
- `TAG` - Image version tag (e.g., `1.21.0`)
- `PROJECT_ID` - GCP project ID (e.g., `ibm-software-mp-project-test`)
- `MP_SERVICE_NAME` - GCP Marketplace service name for image annotation (REQUIRED, no default)
- `TFE_LICENSE` - TFE license content (for registry auth to `images.releases.hashicorp.com`)

**Required env vars (runtime - Kubernetes):**

- `VAULT_LICENSE` - Vault Enterprise license (injected via secret)
- `CONSUL_LICENSE` - Consul Enterprise license (injected via secret)
- `TFE_LICENSE` - TFE license (injected via secret or environment variable)
- `BOUNDARY_LICENSE` - Boundary Enterprise license (injected via Secret Manager)
- `DATABASE_URL` - Connection string for external databases (TFE pre-infra only)
- `ENC_PASSWORD` - Encryption password for data at rest (TFE)

**Optional env vars:**

- `GKE_CLUSTER` - GKE cluster name (default from kubeconfig)
- `GKE_ZONE` - GKE zone (default from kubeconfig)
- `MARKETPLACE_LICENSE` - GCP Marketplace license reference (Boundary Terraform)

**Secrets location:**

- **Git-ignored files:**
  - `*.hclic` - Enterprise license files (product directories)
  - `.env` - Environment variable files
  - `terraform.tfstate*` - Terraform state
  - `.terraform/` - Terraform modules cache

- **GCP Secret Manager:**
  - `boundary-license` - Boundary Enterprise license (created manually or via Terraform)

- **Kubernetes Secrets:**
  - `{app-name}-vault-license` - Vault license
  - `{app-name}-consul-license` - Consul license
  - `{app-name}-tfe-license` - TFE license
  - `{app-name}-tfe-tls-gcp` - TLS certificates (kubernetes.io/tls type)
  - `{app-name}-tfe-ca-gcp` - CA certificate bundle

## Webhooks & Callbacks

**Incoming:**

- Not detected - No incoming webhooks configured

**Outgoing:**

- Not detected - No webhook callbacks to external services
- Optional: GCP Cloud Logging integration (one-way logs push)

---

*Integration audit: 2025-02-24*
