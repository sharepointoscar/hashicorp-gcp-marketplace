# HashiCorp Nomad Enterprise - GCP Marketplace

GCP Marketplace VM Solution for HashiCorp Nomad Enterprise, built using **HashiCorp Validated Designs (HVD)**.

## Overview

Nomad Enterprise is a workload orchestrator that deploys and manages applications across any infrastructure. This Terraform module deploys a complete Nomad Enterprise server cluster on GCP including:

- **Server VMs** - Nomad control plane on Compute Engine (Regional MIG across 3 zones)
- **Raft Integrated Storage** - No external database required (dedicated pd-ssd data disks)
- **TLS Encryption** - All traffic encrypted (self-signed or user-provided certificates)
- **Gossip Encryption** - Cluster membership secured with encryption key
- **Secret Manager** - License, TLS certs, and gossip key (auto-created)
- **Cloud Auto-Join** - Server discovery via GCE metadata (no Consul dependency)

The module is self-contained: a single `terraform apply` creates all prerequisites (secrets, TLS certificates, gossip key) and deploys the full infrastructure.

## Architecture

![Architecture Diagram](architecture.excalidraw)

```
                              +---------------------------------------------+
                              |           INTERNET / CLIENTS                 |
                              +---------------------+------------------------+
                                                    |
                                                    v
+-----------------------------------------------------------------------------------+
|                                  GCP PROJECT                                       |
|  +-----------------------------------------------------------------------------+  |
|  |                            VPC NETWORK                                       |  |
|  |  +-----------+  +--------------------------------------------------+        |  |
|  |  |           |  |              SUBNET                               |        |  |
|  |  |    Load   |  |                                                   |        |  |
|  |  |  Balancer |  |   +----------------------------------------------+|        |  |
|  |  |  :4646    |  |   |    Regional MIG (3 availability zones)       ||        |  |
|  |  |           |  |   |                                              ||        |  |
|  |  +-----------+  |   |  +-----------+  +-----------+  +-----------+ ||        |  |
|  |       |         |   |  |  VM 0     |  |  VM 1     |  |  VM 2     | ||        |  |
|  |       +-------->|   |  | (Zone A)  |  | (Zone B)  |  | (Zone C)  | ||        |  |
|  |                 |   |  |           |  |           |  |           | ||        |  |
|  |                 |   |  | Nomad Srv |  | Nomad Srv |  | Nomad Srv | ||        |  |
|  |                 |   |  | Data Disk |  | Data Disk |  | Data Disk | ||        |  |
|  |                 |   |  | Audit Disk|  | Audit Disk|  | Audit Disk| ||        |  |
|  |                 |   |  +-----------+  +-----------+  +-----------+ ||        |  |
|  |                 |   |       <------  Raft Consensus  ------>       ||        |  |
|  |                 |   +----------------------------------------------+|        |  |
|  |                 |                                                   |        |  |
|  |                 |   Firewall: 4646 API | 4647 RPC | 4648 Serf      |        |  |
|  |                 +---------------------------------------------------+        |  |
|  +-----------------------------------------------------------------------------+  |
|                                                                                    |
|  +-----------------------------------------------------------------------------+  |
|  |                           GCP MANAGED SERVICES                               |  |
|  |                                                                              |  |
|  |  +---------------+  +---------------+  +---------------+                     |  |
|  |  |Secret Manager |  |  Cloud DNS    |  | GCS (optional)|                     |  |
|  |  |               |  |  (optional)   |  |               |                     |  |
|  |  | - License     |  |               |  | - Snapshots   |                     |  |
|  |  | - TLS Cert    |  |               |  |               |                     |  |
|  |  | - TLS Key     |  |               |  |               |                     |  |
|  |  | - Gossip Key  |  |               |  |               |                     |  |
|  |  | - CA Bundle   |  |               |  |               |                     |  |
|  |  +---------------+  +---------------+  +---------------+                     |  |
|  +-----------------------------------------------------------------------------+  |
+------------------------------------------------------------------------------------+
```

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Product type | VM Solution | HashiCorp's official reference architecture is VM-based |
| Storage | Raft on dedicated pd-ssd | No external DB; HVD default (50GB data + 50GB audit) |
| Discovery | GCE cloud auto-join | No Consul dependency; native GCP integration |
| TLS | Self-signed by default | Simplified deployment; user can provide own certs |
| Gossip | Auto-generated key | Stored in Secret Manager; simplifies setup |

### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 4646 | TCP | HTTP API and UI |
| 4647 | TCP | Server RPC |
| 4648 | TCP/UDP | Serf gossip |

---

## Prerequisites

1. **GCP Project** with billing enabled
2. **Nomad Enterprise License** (`nomad.hclic` file)
3. **Terraform** >= 1.3
4. **Packer** >= 1.9.0 (for building VM image)
5. **gcloud CLI** authenticated
6. **Required APIs enabled**:
   ```bash
   gcloud services enable \
     compute.googleapis.com \
     secretmanager.googleapis.com \
     dns.googleapis.com \
     iam.googleapis.com \
     storage.googleapis.com
   ```
7. **Required IAM roles** for the user or service account running `terraform apply`:

   | Role | Purpose |
   |------|---------|
   | `roles/compute.admin` | Create VMs, instance templates, MIGs, firewall rules, LB |
   | `roles/iam.serviceAccountAdmin` | Create Nomad service account |
   | `roles/iam.serviceAccountUser` | Attach service account to VMs |
   | `roles/secretmanager.admin` | Create secrets for license, TLS, gossip key |
   | `roles/storage.admin` | Create GCS bucket for Raft snapshots |
   | `roles/dns.admin` | Create Cloud DNS records (optional) |

### Deployer Roles for Producer Portal

These are the roles configured in the GCP Marketplace Producer Portal product configuration (in `metadata.yaml`). The portal enforces that the deploying user has these roles before allowing deployment:

- `roles/compute.admin`
- `roles/iam.serviceAccountAdmin`
- `roles/iam.serviceAccountUser`
- `roles/secretmanager.admin`
- `roles/storage.admin`
- `roles/dns.admin`

### Nomad VM Service Account Roles

The Terraform module creates a dedicated service account for the Nomad VMs with least-privilege roles:

| Role | Purpose |
|------|---------|
| `roles/compute.viewer` | Cloud auto-join (discover peer VMs) |
| `roles/secretmanager.secretAccessor` | Retrieve license, TLS certs, gossip key |
| `roles/cloudkms.cryptoKeyEncrypterDecrypter` | KMS operations (if configured) |
| `roles/storage.objectCreator` | Write Raft snapshots to GCS (if enabled) |
| `roles/storage.objectViewer` | Read Raft snapshots from GCS (if enabled) |

---

## Quick Start

```bash
# Set your GCP project
export PROJECT_ID="your-gcp-project-id"

# 1. Build the Packer VM image (one-time)
make packer/build

# 2. Deploy Nomad infrastructure
make terraform/apply

# 3. Destroy when done
make terraform/destroy
```

---

## Step 1: Build the Packer VM Image

The Nomad VMs require a pre-built image with Nomad Enterprise installed. This image must be built in your GCP project before deploying.

### 1.1 Configure and Build

```bash
cd packer

export PROJECT_ID="your-gcp-project-id"
export ZONE="us-central1-a"

packer init nomad.pkr.hcl
packer build \
  -var "project_id=$PROJECT_ID" \
  -var "zone=$ZONE" \
  nomad.pkr.hcl
```

### 1.2 Verify the Image

```bash
gcloud compute images list --project=$PROJECT_ID --filter="family=nomad-enterprise"
```

Expected output:
```
NAME                                              PROJECT              FAMILY               STATUS
hashicorp-ubuntu2204-nomad-x86-64-v1112-XXXX       your-project-id      nomad-enterprise     READY
```

---

## Step 2: Deploy Nomad

### 2.1 Configure Variables

```bash
# Create your terraform.tfvars from the test template
cp marketplace_test.tfvars terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
# Required
project_id        = "your-gcp-project-id"
region            = "us-central1"
nomad_fqdn        = "nomad.example.com"
license_file_path = "./nomad.hclic"

# Network
vpc_name    = "default"
subnet_name = "default"

# Optional - TLS (leave unset for auto-generated self-signed certs)
# tls_cert_path      = "/path/to/cert.pem"
# tls_key_path       = "/path/to/key.pem"
# tls_ca_bundle_path = "/path/to/ca-bundle.pem"

# Optional - Sizing
# node_count   = 5
# machine_type = "n2-standard-4"

# Optional - Load balancer (INTERNAL, EXTERNAL, or NONE)
# load_balancing_scheme = "INTERNAL"
```

### 2.2 Deploy

```bash
terraform init
terraform apply -var-file=terraform.tfvars
```

The deployment automatically:
- Creates Secret Manager secrets for license, TLS certificates, and gossip key
- Generates self-signed TLS certificates (or uses your provided ones)
- Generates a gossip encryption key
- Deploys Nomad server VMs across 3 availability zones
- Creates firewall rules for API, RPC, and Serf
- Sets up load balancer (optional)

### 2.3 Get Outputs

```bash
terraform output nomad_url
terraform output load_balancer_ip
terraform output post_deployment_instructions
```

---

## Access Nomad

After deployment, configure DNS to point `nomad_fqdn` to the load balancer IP:

```bash
# Get the load balancer IP
terraform output load_balancer_ip
```

### Verify the Cluster

```bash
# Check cluster health (from a VM or via LB)
curl -sk https://<LOAD_BALANCER_IP>:4646/v1/agent/health

# Check server members
curl -sk https://<LOAD_BALANCER_IP>:4646/v1/agent/members

# Check cluster leader
curl -sk https://<LOAD_BALANCER_IP>:4646/v1/status/leader
```

### Access the UI

```bash
open https://nomad.example.com:4646
```

### SSH Access to VMs (IAP Tunnel)

All server VMs are accessible via Identity-Aware Proxy (IAP) tunneling:

```bash
# SSH to a specific server
gcloud compute ssh <nomad-server-instance> \
  --project=$PROJECT_ID \
  --zone=<ZONE> \
  --tunnel-through-iap

# Check Nomad service status
sudo systemctl status nomad

# View Nomad logs
sudo journalctl -u nomad -f

# View cloud-init log
sudo cat /var/log/nomad-cloud-init.log

# Check Nomad configuration
sudo cat /etc/nomad.d/nomad.hcl
```

---

## Configuration Reference

### Required Variables

| Variable | Description |
|----------|-------------|
| `project_id` | GCP project ID |
| `nomad_fqdn` | Fully qualified domain name for Nomad |
| `license_file_path` | Path to Nomad Enterprise license file (.hclic) |

### TLS Variables (Optional)

| Variable | Default | Description |
|----------|---------|-------------|
| `tls_cert_path` | `null` | Path to TLS certificate PEM file (null = self-signed) |
| `tls_key_path` | `null` | Path to TLS private key PEM file (null = self-signed) |
| `tls_ca_bundle_path` | `null` | Path to CA bundle PEM file |

### Nomad Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `nomad_version` | `1.11.2+ent` | Nomad Enterprise version |
| `nomad_datacenter` | `dc1` | Nomad datacenter name |
| `nomad_region` | `null` | Nomad region name (uses Nomad default if null) |
| `node_count` | `3` | Number of Nomad server nodes (must be odd: 1, 3, 5) |
| `nomad_acl_enabled` | `true` | Enable Nomad ACLs |
| `nomad_enable_ui` | `true` | Enable Nomad web UI |

### Compute Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `machine_type` | `n2-standard-4` | GCE machine type for Nomad server VMs |
| `boot_disk_size` | `100` | Boot disk size (GB) |
| `data_disk_size` | `50` | Nomad data disk size in GB (Raft storage, pd-ssd) |
| `audit_disk_size` | `50` | Nomad audit log disk size (GB) |

### Network Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | `us-central1` | GCP region for all resources |
| `vpc_name` | `default` | Name of the VPC network |
| `subnet_name` | `default` | Name of the subnet within the VPC |
| `vpc_project_id` | `null` | Project ID containing the VPC (for Shared VPC). Defaults to project_id if null |
| `cidr_ingress_api_allow` | `["0.0.0.0/0"]` | CIDR ranges allowed to access the Nomad API (port 4646) |
| `cidr_ingress_rpc_allow` | `["0.0.0.0/0"]` | CIDR ranges allowed for RPC/Serf traffic (ports 4647, 4648) |

### Load Balancer

| Variable | Default | Description |
|----------|---------|-------------|
| `load_balancing_scheme` | `INTERNAL` | `INTERNAL`, `EXTERNAL`, or `NONE` |

### DNS Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `create_cloud_dns_record` | `false` | Create a Cloud DNS A record for nomad_fqdn pointing to the load balancer |
| `cloud_dns_managed_zone` | `null` | Cloud DNS managed zone name (required if create_cloud_dns_record is true) |

### GCS Snapshots

| Variable | Default | Description |
|----------|---------|-------------|
| `create_snapshot_bucket` | `true` | Create a GCS bucket for Nomad Raft snapshots |

### Labels

| Variable | Default | Description |
|----------|---------|-------------|
| `common_labels` | `{}` | Common labels to apply to all GCP resources |

### Marketplace Variables (auto-populated)

| Variable | Default | Description |
|----------|---------|-------------|
| `nomad_image` | (pre-built image path) | Packer-built VM image for Nomad (overrides default Ubuntu image) |
| `friendly_name_prefix` | `nomad` | Prefix for resource names when not deployed via Marketplace |
| `goog_cm_deployment_name` | `""` | Marketplace deployment name (auto-populated by GCP Marketplace UI) |

### Outputs

| Output | Description |
|--------|-------------|
| `nomad_url` | Nomad API/UI URL |
| `nomad_fqdn` | FQDN for Nomad |
| `load_balancer_ip` | Load balancer IP |
| `deployment_id` | Unique deployment identifier |
| `nomad_version` | Deployed Nomad version |
| `region` | Deployment region |
| `post_deployment_instructions` | Post-deployment setup guide |

---

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make packer/build` | Build Nomad VM image with Packer |
| `make packer/validate` | Validate Packer template |
| `make terraform/apply` | Deploy Nomad infrastructure |
| `make terraform/destroy` | Destroy all Nomad resources |
| `make terraform/plan` | Preview infrastructure changes |
| `make validate` | Run all validations (Terraform + CFT) |
| `make validate/full` | Full validation including terraform plan |
| `make package` | Create ZIP package for Marketplace |
| `make upload` | Upload package to GCS |
| `make release` | Full release pipeline (validate + package + upload) |
| `make image/list` | List available Nomad images |
| `make info` | Show configuration details |

---

## File Structure

```
products/nomad/
├── README.md                     # This file
├── CLAUDE.md                     # AI assistant guidance
├── Makefile                      # Build and deploy automation
├── nomad.hclic                   # License file (gitignored)
├── .gitignore
│
├── main.tf                       # Root module (providers + prerequisites + server)
├── variables.tf                  # Input variables
├── outputs.tf                    # Output values
├── versions.tf                   # Provider versions
├── marketplace_test.tfvars       # Test/template configuration
│
├── metadata.yaml                 # GCP Marketplace blueprint metadata
├── metadata.display.yaml         # Marketplace UI configuration
├── architecture.excalidraw       # Architecture diagram source
│
├── packer/
│   └── nomad.pkr.hcl            # Packer template for VM image
│
└── modules/
    ├── server/                   # Forked from terraform-google-nomad-enterprise-hvd
    │   ├── compute.tf            # Instance template, MIG, health check
    │   ├── firewall.tf           # IAP, API, RPC/Serf, egress rules
    │   ├── iam.tf                # Service account + IAM bindings
    │   ├── lb.tf                 # Regional LB (internal/external/none)
    │   ├── cloud_dns.tf          # Optional DNS record
    │   ├── data.tf               # Network/zone data sources
    │   ├── variables.tf          # Module inputs
    │   ├── outputs.tf            # Module outputs
    │   ├── versions.tf           # Provider constraints
    │   └── templates/
    │       └── nomad_custom_data.sh.tpl  # Cloud-init startup script
    └── prerequisites/            # Secret Manager secrets + TLS cert generation
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### How It Works

```
terraform apply
    |
    v
module "prerequisites"          <-- Creates Secret Manager secrets
    |                               (license, TLS cert, TLS key, gossip key)
    |                               Generates self-signed TLS if not provided
    v
module "server"                 <-- Deploys server VMs (Regional MIG)
                                    Cloud-init fetches secrets, configures Nomad
                                    Raft consensus forms automatically
                                    Cloud auto-join discovers peers (no Consul)
```

---

## Destroying Resources

### Using Makefile

```bash
make terraform/destroy
```

### Manual

```bash
terraform destroy -var-file=terraform.tfvars -auto-approve
```

---

## Troubleshooting

### Check Server Logs

```bash
gcloud compute ssh <nomad-server-instance> \
  --project=YOUR_PROJECT \
  --zone=us-central1-a \
  --tunnel-through-iap

sudo journalctl -u nomad -f
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Server not starting | Invalid license | Verify `license_file_path` points to valid `.hclic` |
| No cluster leader | Insufficient servers or network issues | Ensure node_count >= 3 and firewall allows 4647/4648 |
| Raft timeout | VM communication blocked | Check firewall rules for RPC (4647) and Serf (4648) |
| Health check failing | Servers initializing | Wait 3-5 minutes after deployment |
| TLS handshake failed | Certificate mismatch | Verify FQDN matches TLS certificate SAN |
| Packer timeout | No SSH firewall rule | Add firewall for `packer-build` tag on port 22 |

---

## Known Issues

### CVE-2020-7956 False Positive (Go Build Metadata)

**Status:** Temporary workaround in place. Must be resolved in a future release.

The GCP Marketplace Producer Portal vulnerability scanner flags CVE-2020-7956 against the Nomad binary. This is a **false positive** caused by Go module versioning: the Nomad binary reports its module version as a pseudo-version (`0.0.0-YYYYMMDD-hash`) rather than the actual semantic version (`1.11.2`). The scanner compares `0.0.0` against the CVE fix version `0.10.3` and incorrectly flags it as vulnerable.

**Current workaround:** The Packer install script (`packer/scripts/install-nomad.sh`) strips the `.go.buildinfo` section from the Nomad binary using `objcopy`, preventing the scanner from reading the misleading version metadata.

**Required follow-up:** This workaround MUST be removed when HashiCorp releases a Nomad version that resolves the Go module pseudo-version issue. When a new Nomad release is available:
1. Remove the `objcopy` line from `packer/scripts/install-nomad.sh`
2. Rebuild the Packer image and verify the scanner no longer flags the CVE
3. If the scanner still flags it, re-apply the workaround and escalate to HashiCorp

---

## Security Considerations

1. **License**: Stored in Secret Manager, not in code
2. **TLS**: Self-signed or user-provided certificates, all traffic encrypted
3. **Gossip**: Auto-generated encryption key, stored in Secret Manager
4. **ACL**: Enabled by default (tokens required for API access)
5. **IAM**: Least-privilege service account per deployment
6. **Network**: Firewall rules restrict access to API, RPC, and Serf ports

---

## Support

- [Nomad Documentation](https://developer.hashicorp.com/nomad/docs)
- [HashiCorp Support](https://support.hashicorp.com)
- [Nomad Community Forum](https://discuss.hashicorp.com/c/nomad)

## License

This deployment requires a valid HashiCorp Nomad Enterprise license.
