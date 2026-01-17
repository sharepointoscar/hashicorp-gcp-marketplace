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

### 1. Place Your License File

```bash
cd products/boundary

# Place your Boundary Enterprise license file (gitignored)
cp /path/to/your/boundary.hclic .
```

### 2. Configure Variables

```bash
cd test

# Copy the example and edit with your values
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
project_id        = "your-gcp-project-id"
region            = "us-central1"
boundary_fqdn     = "boundary.example.com"
license_file_path = "../boundary.hclic"

vpc_name               = "default"
controller_subnet_name = "default"
```

### 3. Deploy

```bash
cd products/boundary/test

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy (creates secrets, TLS certs, and full Boundary deployment)
terraform apply
```

The deployment automatically:
- Creates Secret Manager secrets for license, TLS certificates, and database password
- Generates self-signed TLS certificates (or uses provided ones)
- Deploys Boundary controllers and workers
- Creates Cloud SQL PostgreSQL database
- Sets up Cloud KMS encryption keys

### 4. Access Boundary

After deployment:

```bash
# Get the Boundary URL
terraform output boundary_url

# Get the controller load balancer IP
terraform output controller_load_balancer_ip
```

Configure DNS to point `boundary_fqdn` to the load balancer IP, then access:
- UI: `https://boundary.example.com:9200`
- API: `https://boundary.example.com:9200`

## Configuration

### Required Variables

| Variable | Description |
|----------|-------------|
| `project_id` | GCP project ID |
| `region` | GCP region (e.g., `us-central1`) |
| `boundary_fqdn` | Fully qualified domain name for Boundary |
| `license_file_path` | Path to Boundary Enterprise license file |
| `vpc_name` | VPC network name |
| `controller_subnet_name` | Subnet name for controllers |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `boundary_version` | `0.21.0+ent` | Boundary Enterprise version |
| `controller_instance_count` | `1` | Number of controller instances |
| `controller_machine_type` | `n2-standard-4` | Controller VM machine type |
| `deploy_ingress_worker` | `true` | Deploy ingress worker |
| `deploy_egress_worker` | `false` | Deploy egress worker |
| `ingress_worker_instance_count` | `1` | Number of ingress workers |
| `egress_worker_instance_count` | `1` | Number of egress workers |
| `tls_cert_path` | `null` | Path to TLS cert (null = self-signed) |
| `tls_key_path` | `null` | Path to TLS key (null = self-signed) |

## Outputs

| Output | Description |
|--------|-------------|
| `boundary_url` | Boundary API/UI URL |
| `controller_load_balancer_ip` | Controller load balancer IP |
| `post_deployment_instructions` | Next steps after deployment |

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
│   ├── worker/               # Worker HVD module
│   └── prerequisites/        # Secrets and TLS automation
│
└── test/
    ├── main.tf               # Test deployment
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars      # Your config (gitignored)
    └── terraform.tfvars.example
```

## Troubleshooting

### Check Controller Logs

```bash
# SSH to controller (via IAP)
gcloud compute ssh <controller-instance> \
  --project=YOUR_PROJECT \
  --zone=us-central1-a \
  --tunnel-through-iap

# View logs
sudo journalctl -u boundary -f
```

### Check Worker Logs

```bash
gcloud compute ssh <worker-instance> \
  --project=YOUR_PROJECT \
  --zone=us-central1-a \
  --tunnel-through-iap

sudo journalctl -u boundary -f
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Controller not starting | Invalid license | Verify license file path |
| Workers not connecting | Network/firewall | Check firewall rules for port 9201 |
| Database connection failed | Cloud SQL not ready | Wait for Cloud SQL provisioning |
| Health check failing | Controllers initializing | Wait 5-10 minutes after deployment |

## Security Considerations

1. **License Storage**: License stored in GCP Secret Manager, not in code
2. **TLS**: All communication encrypted with TLS (self-signed or provided)
3. **KMS**: Encryption keys managed by Cloud KMS
4. **IAM**: Least-privilege service accounts for each component
5. **Network**: Controllers and workers isolated in appropriate subnets
6. **Database Password**: Randomly generated and stored in Secret Manager

## Support

- [Boundary Documentation](https://developer.hashicorp.com/boundary/docs)
- [HashiCorp Support](https://support.hashicorp.com)
- [Boundary Community Forum](https://discuss.hashicorp.com/c/boundary)

## License

This deployment requires a valid HashiCorp Boundary Enterprise license.
