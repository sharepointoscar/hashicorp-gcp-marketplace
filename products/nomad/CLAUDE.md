# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Product Overview

This is a **GCP Marketplace VM Solution** for HashiCorp Nomad Enterprise. Unlike the Kubernetes-based products (Consul, Vault, TFE), Nomad uses Terraform modules to deploy VMs on Compute Engine.

## Architecture

Nomad Enterprise uses the HashiCorp Validated Design (HVD) pattern:
- **Server VMs** - Regional MIG across 3 availability zones running Nomad servers
- **Raft Integrated Storage** - No external database required
- **Secret Manager** - License, TLS certificates, gossip encryption key
- **GCS** - Raft snapshot storage (optional)
- **Load Balancer** - Internal or External for API/UI access

Key differences from Boundary:
| Aspect | Boundary | Nomad |
|--------|----------|-------|
| HVD Modules | 2 (controller + worker) | 1 (server) |
| External DB | Cloud SQL PostgreSQL | None (Raft) |
| KMS | 4 keys | None |
| Secret Manager | License, TLS, DB pass | License, TLS, gossip key |
| Disks | 1 boot | 3 (boot + data + audit) |
| CNI Plugins | No | Yes |

## Build & Validation Commands

**Prerequisites:**
```bash
# Authenticate to GCP
gcloud auth login && gcloud auth application-default login

# License file should be at: products/nomad/nomad exp Mar 31 2026.hclic
```

**Standard Validation Workflow (USE THIS):**
```bash
# Run all validations (terraform + CFT metadata)
make validate

# Run full validation including terraform plan
make validate/full
```

**Full Release (validate + package + upload):**
```bash
make release
```

**Individual Targets:**
```bash
make terraform/validate  # Validate Terraform configuration
make cft/validate        # Validate CFT metadata (requires CFT CLI)
make terraform/plan      # Run terraform plan with marketplace_test.tfvars
make package             # Create ZIP package
make upload              # Upload package to GCS
```

**CRITICAL WARNINGS:**
- **NEVER run `make clean` if you have existing terraform state** - it deletes `*.tfstate*` files!
- **NEVER run `make gcs/clean`** unless you want to remove the GCS package
- To clean only build artifacts without deleting state: `rm -rf .build`

**Full Deployment Test:**
```bash
# Initialize and apply
terraform init
terraform apply -var-file=marketplace_test.tfvars -var="project_id=$PROJECT_ID"

# Verify health
curl -k https://<NOMAD_FQDN>:4646/v1/agent/health

# Cleanup
terraform destroy -var-file=marketplace_test.tfvars -var="project_id=$PROJECT_ID"
```

## File Structure

```
products/nomad/
├── README.md                 # User documentation
├── CLAUDE.md                 # This file
├── .gitignore
├── nomad.hclic               # License (gitignored)
│
├── main.tf                   # Root module orchestration
├── variables.tf              # Input variables
├── outputs.tf                # Output values
├── versions.tf               # Provider constraints
│
├── metadata.yaml             # GCP Marketplace blueprint
├── metadata.display.yaml     # Marketplace UI configuration
│
├── Makefile                  # Packer, Terraform, CFT, package, upload
│
├── modules/
│   ├── prerequisites/        # Secret Manager, TLS, GCS bucket, API enablement
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   └── server/               # Forked from terraform-google-nomad-enterprise-hvd
│       ├── compute.tf        # Instance template, MIG, health check
│       ├── firewall.tf       # IAP, API, RPC/Serf, egress rules
│       ├── iam.tf            # Service account + IAM bindings
│       ├── lb.tf             # Regional LB (internal/external/none)
│       ├── cloud_dns.tf      # Optional DNS record
│       ├── data.tf           # Network/zone data sources
│       ├── variables.tf      # Module inputs
│       ├── outputs.tf        # nomad_url, nomad_cli_config
│       ├── versions.tf
│       └── templates/
│           └── nomad_custom_data.sh.tpl  # Cloud-init startup script
│
├── packer/                   # Pre-baked VM image
│   ├── nomad.pkr.hcl
│   └── scripts/
│       └── install-nomad.sh
│
└── marketplace_test.tfvars   # Example test vars
```

## HVD Module

The `modules/server/` directory contains a forked version of HashiCorp's official HVD module:

- **Source**: `hashicorp/terraform-google-nomad-enterprise-hvd`
- **Creates**: Regional MIG (3 zones), instance templates (3 disks), firewall rules, IAM, LB, DNS

### Marketplace Adaptations

When forking the HVD module, these changes were made:
1. Relaxed Terraform version from `~>1.9` to `~>1.3`
2. Updated `nomad_version` default to `1.11.2+ent`
3. Reduced `node_count` default to `3` (from `6`)
4. Reduced `nomad_data_disk_size` default to `50` (from `500`)
5. Added idempotent checks in cloud-init for pre-baked images
6. Removed `nomad_metadata_template` validation (breaks as submodule)
7. Added `packer_image` support in instance template

## Pre-Baked VM Image Architecture (CRITICAL)

**This deployment uses a Packer-built VM image with Nomad pre-installed.** The cloud-init scripts MUST be idempotent and skip installation steps when software is already present.

### Why Pre-Baked Images?
1. **GCP Marketplace requirement**: Faster deployment, no external downloads
2. **Security**: No runtime internet egress needed from VMs
3. **Reliability**: No dependency on releases.hashicorp.com availability

### Cloud-Init Template Design Principles

**Location**: `modules/server/templates/nomad_custom_data.sh.tpl`

**REQUIRED idempotency modifications for pre-baked images:**

1. **Package installation (`install_prereqs`)** - Check if packages exist before apt-get
2. **Binary installation (`install_nomad_binary`)** - Skip download if `/usr/bin/nomad` exists
3. **User/group creation (`user_group_create`)** - Ignore "already exists" errors
4. **CNI plugin installation (`install_cni_plugins`)** - Skip if `/opt/cni/bin/bridge` exists
5. **Checksum verification (`checksum_verify`)** - Skip if binary already present

### Pre-Baked Image Details
- **Image Name**: `hashicorp-ubuntu2204-nomad-x86-64-v1112-YYYYMMDD`
- **Image Family**: `nomad-enterprise`
- **Built With**: Packer (`make packer/build`)

The image includes:
- Nomad Enterprise binary (`/usr/bin/nomad`)
- CNI plugins (`/opt/cni/bin/`)
- `nomad` user and group
- Required packages: `jq`, `unzip`, `gcloud SDK`
- Systemd service template

### Testing Cloud-Init Changes

After modifying templates:
1. Run `terraform apply` to update instance templates
2. Trigger rolling update: `gcloud compute instance-groups managed rolling-action replace <MIG> --region=<region> --max-unavailable=3`
3. SSH to VM and check: `cat /var/log/nomad-cloud-init.log`

## Version Synchronization

These files must have matching versions:
- `metadata.yaml` → `spec.info.version`
- `variables.tf` → `nomad_version` default
- `Makefile` → `VERSION` and `NOMAD_VERSION`
- Root module documentation

Current target: **1.11.2+ent**

## GCP Marketplace VM Solution Requirements

### Terraform Requirements
- Approved providers only: `google`, `google-beta`, `random`, `tls`
- Must include `project_id` variable
- Must include `goog_cm_deployment_name` for UI deployments

### Metadata Requirements
- `metadata.yaml` - CFT Blueprint format
- `metadata.display.yaml` - UI form customization
- Validation: `cft blueprint metadata -p . -v`

### Producer Portal Submission
1. Build VM image: `make packer/build`
2. Upload Terraform package: `make release`
3. Configure in Producer Portal with GCS path and VM image
4. Validate in Producer Portal (up to 2 hours)
5. Test via "Deployment preview"
6. Submit for review

## Debugging

### Server Issues
```bash
# SSH via IAP
gcloud compute ssh <instance-name> --tunnel-through-iap

# Check service status
sudo systemctl status nomad

# View logs
sudo journalctl -u nomad -f

# Check cloud-init log
cat /var/log/nomad-cloud-init.log

# Check config
sudo cat /etc/nomad.d/nomad.hcl

# Verify cluster membership
nomad server members
nomad node status
```

### Health Check
```bash
# API health
curl -k https://<NOMAD_FQDN>:4646/v1/agent/health

# Agent self info
curl -k https://<NOMAD_FQDN>:4646/v1/agent/self
```

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| License invalid | Wrong license file | Verify .hclic is for Nomad Enterprise |
| Gossip mismatch | Key rotation or misconfiguration | Check gossip key in Secret Manager |
| TLS handshake failed | Certificate SAN mismatch | Verify TLS cert includes `server.dc1.nomad` SAN |
| Raft peers not found | Nodes can't reach each other | Check firewall rules for ports 4647/4648 |
| Health check timeout | Servers initializing | Wait 3-5 min, check nomad logs |
| ACL bootstrap failed | Already bootstrapped | Bootstrap token stored in cloud-init log on first node |

## Nomad Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 4646 | TCP | HTTP API and Web UI |
| 4647 | TCP | RPC (server-to-server) |
| 4648 | TCP/UDP | Serf gossip (cluster membership) |

## Security Notes

1. **License**: Stored in Secret Manager, never in code or images
2. **TLS**: Auto-generated self-signed or user-provided certificates
3. **Gossip**: Auto-generated encryption key for cluster membership
4. **ACLs**: Enabled by default, must bootstrap after first deployment
5. **IAM**: Least-privilege service accounts (compute.viewer, secretmanager.secretAccessor)

## Related Documentation

- [Nomad Documentation](https://developer.hashicorp.com/nomad/docs)
- [Nomad Enterprise Features](https://developer.hashicorp.com/nomad/docs/enterprise)
- [HVD Module](https://github.com/hashicorp/terraform-google-nomad-enterprise-hvd)
- [GCP Marketplace VM Solutions](https://cloud.google.com/marketplace/docs/partners/vm)
- [CFT Blueprint Metadata](https://cloud.google.com/docs/terraform/blueprints/terraform-blueprints)
