# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Product Overview

This is a **GCP Marketplace VM Solution** for HashiCorp Boundary Enterprise. Unlike the Kubernetes-based products (Consul, Vault, TFE), Boundary uses Terraform modules to deploy VMs on Compute Engine.

## Architecture

Boundary Enterprise uses the HashiCorp Validated Design (HVD) pattern:
- **Controllers** - Compute Engine VMs running Boundary control plane
- **Workers** - Ingress (public) and Egress (private) workers
- **Cloud SQL PostgreSQL** - Database backend
- **Cloud KMS** - Encryption keys (root, worker, recovery, BSR)
- **GCS** - Backup and Session Recording (BSR) storage
- **Secret Manager** - License and credential storage

## Key Differences from K8s Products

| Aspect | Consul/Vault/TFE | Boundary |
|--------|------------------|----------|
| Listing Type | Kubernetes App | VM Solution |
| Deployment | Click-to-Deploy (mpdev) | Terraform apply |
| Metadata | schema.yaml | metadata.yaml (CFT) |
| Validation | mpdev verify | cft blueprint metadata |
| Images | Container images | VM binary install |

## Build & Validation Commands

**Prerequisites:**
```bash
# Authenticate to GCP
gcloud auth login && gcloud auth application-default login

# Store license in Secret Manager
gcloud secrets create boundary-license --data-file=boundary.hclic
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
curl -k https://<BOUNDARY_FQDN>:9200/health

# Cleanup
terraform destroy -var-file=marketplace_test.tfvars -var="project_id=$PROJECT_ID"
```

## File Structure

```
products/boundary/
├── README.md                 # User documentation
├── CLAUDE.md                 # This file
├── .gitignore
├── boundary.hclic            # License (gitignored)
│
├── main.tf                   # Root module orchestration
├── variables.tf              # Input variables
├── outputs.tf                # Output values
├── versions.tf               # Provider constraints
│
├── metadata.yaml             # GCP Marketplace blueprint
├── metadata.display.yaml     # Marketplace UI configuration
│
├── modules/
│   ├── controller/           # Forked from terraform-google-boundary-enterprise-controller-hvd
│   └── worker/               # Forked from terraform-google-boundary-enterprise-worker-hvd
│
└── examples/
    └── marketplace_test/
        ├── main.tf
        └── marketplace_test.tfvars
```

## HVD Modules

The `modules/` directory contains forked versions of HashiCorp's official HVD modules:

- **Controller Module**: `hashicorp/terraform-google-boundary-enterprise-controller-hvd`
  - Creates controller VMs, Cloud SQL, KMS keys, load balancers
  - ~60 GCP resources

- **Worker Module**: `hashicorp/terraform-google-boundary-enterprise-worker-hvd`
  - Creates worker VMs with optional load balancer
  - Supports ingress (public) and egress (private) configurations

### Marketplace Adaptations

When forking HVD modules, these changes are needed:
1. Add `goog_cm_deployment_name` variable for unique resource naming
2. Verify only approved Terraform providers are used
3. Update `boundary_version` default to latest (0.21.0+ent)

## Version Synchronization

These files must have matching versions:
- `metadata.yaml` → `spec.info.version`
- `variables.tf` → `boundary_version` default
- Root module documentation

Current target: **0.21.0+ent**

## GCP Marketplace VM Solution Requirements

### Terraform Requirements
- Approved providers only: `google`, `google-beta`, `random`, `time`, `tls`, `null`
- Must include `project_id` variable
- Must include `goog_cm_deployment_name` for UI deployments

### Metadata Requirements
- `metadata.yaml` - CFT Blueprint format
- `metadata.display.yaml` - UI form customization
- Validation: `cft blueprint metadata -p . -v`

### Producer Portal Submission
1. Upload Terraform package to Cloud Storage (versioned bucket)
2. Validate in Producer Portal (up to 2 hours)
3. Test via "Deployment preview"
4. Submit for review

## Debugging

### Controller Issues
```bash
# SSH via IAP
gcloud compute ssh boundary-controller-0 --tunnel-through-iap

# Check service status
sudo systemctl status boundary

# View logs
sudo journalctl -u boundary -f

# Check config
sudo cat /etc/boundary.d/boundary.hcl
```

### Worker Issues
```bash
gcloud compute ssh boundary-worker-0 --tunnel-through-iap

# Check worker registration
sudo journalctl -u boundary | grep "worker successfully"

# Verify upstream connection
curl -k https://<CONTROLLER_LB>:9201/v1/health
```

### Database Issues
```bash
# Connect to Cloud SQL (from controller)
psql "postgresql://boundary:PASSWORD@CLOUD_SQL_IP:5432/boundary?sslmode=require"

# Check tables
\dt
SELECT count(*) FROM boundary_schema_version;
```

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| License invalid | Wrong license file | Verify boundary.hclic is for Boundary Enterprise |
| Worker auth failed | Clock skew or KMS issue | Check NTP sync, verify KMS permissions |
| DB connection refused | Cloud SQL not ready | Wait for provisioning, check private service access |
| Health check timeout | Controllers initializing | Wait 5-10 min, check controller logs |
| `iam.managed.disableServiceAccountKeyCreation` | Org policy blocks SA key creation | Request org policy exception or use workload identity |
| `proxy-only subnetwork is required` | Missing proxy subnet for internal LB | Create proxy-only subnet in VPC for the region |

## GCP Org Policy Issues

Some GCP organizations have security policies that block certain operations:

**Service Account Key Creation Blocked:**
```
Error: Operation denied by org policy: ["constraints/iam.managed.disableServiceAccountKeyCreation"]
```
- The module creates SA keys for Boundary to authenticate to GCP services
- Request an exception for your project, or modify the module to use workload identity

**Proxy-Only Subnet Required:**
```
Error: An active proxy-only subnetwork is required in the same region and VPC
```
- Internal TCP proxy load balancers require a proxy-only subnet
- Create one manually: `gcloud compute networks subnets create proxy-subnet --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE --region=us-central1 --network=default --range=10.129.0.0/23`

## Security Notes

1. **License**: Stored in Secret Manager, never in code or images
2. **TLS**: Auto-generated or user-provided certificates
3. **KMS**: Separate keys for root, worker, recovery, and BSR
4. **IAM**: Least-privilege service accounts
5. **Network**: Controllers in public subnet (API access), workers span public/private

## Related Documentation

- [Boundary Documentation](https://developer.hashicorp.com/boundary/docs)
- [HVD Controller Module](https://github.com/hashicorp/terraform-google-boundary-enterprise-controller-hvd)
- [HVD Worker Module](https://github.com/hashicorp/terraform-google-boundary-enterprise-worker-hvd)
- [GCP Marketplace VM Solutions](https://cloud.google.com/marketplace/docs/partners/vm)
- [CFT Blueprint Metadata](https://cloud.google.com/docs/terraform/blueprints/terraform-blueprints)
