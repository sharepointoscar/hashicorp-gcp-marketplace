# HashiCorp Boundary Enterprise - GCP Marketplace

This directory contains the GCP Marketplace VM Solution for HashiCorp Boundary Enterprise.

## Overview

Boundary Enterprise provides secure remote access to infrastructure without exposing networks or managing credentials. This deployment uses HashiCorp's Validated Design (HVD) architecture with:

- **Controllers** - Boundary control plane on Compute Engine VMs
- **Workers** - Ingress and egress workers for session proxying
- **Cloud SQL PostgreSQL** - Database backend
- **Cloud KMS** - Encryption key management
- **GCS** - Backup and session recording storage (BSR)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         PUBLIC SUBNET                            │
│  ┌─────────────┐    ┌──────────────────────────────────────┐    │
│  │   Ingress   │    │      Boundary Control Plane          │    │
│  │   Worker    │    │   (Controllers across multiple AZs)  │    │
│  └──────┬──────┘    └──────────────────────────────────────┘    │
│         │                          │                             │
├─────────┼──────────────────────────┼─────────────────────────────┤
│         │        PRIVATE SUBNET    │                             │
│         ▼                          ▼                             │
│  ┌─────────────┐           ┌──────────────┐   ┌──────────────┐  │
│  │   Egress    │           │   Cloud SQL  │   │   Cloud KMS  │  │
│  │   Worker    │           │  PostgreSQL  │   │              │  │
│  └──────┬──────┘           └──────────────┘   └──────────────┘  │
│         │                                                        │
│         ▼                                                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │   Target    │  │   Target    │  │   Target    │              │
│  │    Host     │  │    Host     │  │    Host     │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **GCP Project** with billing enabled
2. **Boundary Enterprise License** (`.hclic` file)
3. **Terraform** >= 1.5.0
4. **gcloud CLI** authenticated
5. **Required APIs enabled**:
   - Compute Engine API
   - Cloud SQL Admin API
   - Cloud KMS API
   - Secret Manager API
   - Cloud DNS API (optional)

## Quick Start

### 1. Clone and Configure

```bash
cd products/boundary

# Place your license file (gitignored)
cp /path/to/your/boundary.hclic .
```

### 2. Set Required Variables

Create a `terraform.tfvars` file:

```hcl
# Required
project_id              = "your-gcp-project-id"
boundary_fqdn           = "boundary.example.com"
boundary_license_secret = "projects/PROJECT/secrets/boundary-license/versions/latest"

# Network
vpc_name    = "boundary-vpc"
subnet_name = "boundary-subnet"
region      = "us-central1"

# Optional: Customize sizing
controller_instance_count = 3
worker_instance_count     = 2
controller_machine_type   = "e2-medium"
worker_machine_type       = "e2-medium"
```

### 3. Store License in Secret Manager

```bash
# Create secret
gcloud secrets create boundary-license \
  --project=YOUR_PROJECT_ID \
  --replication-policy="automatic"

# Add license content
gcloud secrets versions add boundary-license \
  --project=YOUR_PROJECT_ID \
  --data-file=boundary.hclic
```

### 4. Deploy

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply
terraform apply
```

### 5. Access Boundary

After deployment:

```bash
# Get the Boundary URL
terraform output boundary_url

# Get initial admin credentials (stored in Secret Manager)
gcloud secrets versions access latest \
  --secret=boundary-admin-password \
  --project=YOUR_PROJECT_ID
```

## Configuration

### Required Variables

| Variable | Description |
|----------|-------------|
| `project_id` | GCP project ID |
| `boundary_fqdn` | Fully qualified domain name for Boundary |
| `boundary_license_secret` | Secret Manager path to license |
| `vpc_name` | VPC network name |
| `subnet_name` | Subnet name |
| `region` | GCP region |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `boundary_version` | `0.21.0+ent` | Boundary Enterprise version |
| `controller_instance_count` | `3` | Number of controller instances |
| `worker_instance_count` | `2` | Number of worker instances |
| `controller_machine_type` | `e2-medium` | Controller VM machine type |
| `worker_machine_type` | `e2-medium` | Worker VM machine type |
| `enable_session_recording` | `false` | Enable BSR session recording |
| `db_instance_tier` | `db-custom-2-4096` | Cloud SQL instance tier |

## Outputs

| Output | Description |
|--------|-------------|
| `boundary_url` | Boundary API/UI URL |
| `controller_ips` | Controller instance IPs |
| `worker_ips` | Worker instance IPs |
| `database_connection` | Cloud SQL connection string |

## Testing

### Validate Configuration

```bash
# Validate Terraform
terraform validate

# Validate Marketplace metadata (requires CFT CLI)
cft blueprint metadata -p . -v
```

### Test Deployment

```bash
# Use test configuration
terraform plan -var-file=examples/marketplace_test/marketplace_test.tfvars

# Health check after deployment
curl -k https://<BOUNDARY_FQDN>:9200/health
```

## Troubleshooting

### Check Controller Logs

```bash
# SSH to controller (via IAP)
gcloud compute ssh boundary-controller-0 \
  --project=YOUR_PROJECT \
  --zone=us-central1-a \
  --tunnel-through-iap

# View logs
sudo journalctl -u boundary -f
```

### Check Worker Logs

```bash
gcloud compute ssh boundary-worker-0 \
  --project=YOUR_PROJECT \
  --zone=us-central1-a \
  --tunnel-through-iap

sudo journalctl -u boundary -f
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Controller not starting | Invalid license | Verify license in Secret Manager |
| Workers not connecting | Network/firewall | Check firewall rules for port 9201 |
| Database connection failed | Cloud SQL not ready | Wait for Cloud SQL provisioning |
| Health check failing | Controllers initializing | Wait 5-10 minutes after deployment |

## File Structure

```
products/boundary/
├── README.md                 # This file
├── CLAUDE.md                 # AI assistant guidance
├── boundary.hclic            # License file (gitignored)
├── .gitignore
│
├── main.tf                   # Root module
├── variables.tf              # Input variables
├── outputs.tf                # Output values
├── versions.tf               # Provider versions
│
├── metadata.yaml             # GCP Marketplace metadata
├── metadata.display.yaml     # Marketplace UI config
│
├── modules/
│   ├── controller/           # Controller HVD module
│   └── worker/               # Worker HVD module
│
└── examples/
    └── marketplace_test/
        ├── main.tf
        └── marketplace_test.tfvars
```

## Security Considerations

1. **License Storage**: License stored in GCP Secret Manager, not in code
2. **TLS**: All communication encrypted with TLS
3. **KMS**: Encryption keys managed by Cloud KMS
4. **IAM**: Least-privilege service accounts for each component
5. **Network**: Controllers and workers isolated in appropriate subnets

## Support

- [Boundary Documentation](https://developer.hashicorp.com/boundary/docs)
- [HashiCorp Support](https://support.hashicorp.com)
- [Boundary Community Forum](https://discuss.hashicorp.com/c/boundary)

## License

This deployment requires a valid HashiCorp Boundary Enterprise license.
