# HashiCorp Boundary Enterprise - GCP Marketplace

GCP Marketplace VM Solution for HashiCorp Boundary Enterprise, built using **HashiCorp Validated Designs (HVD)**.

## Overview

Boundary Enterprise provides secure remote access to infrastructure without exposing networks or managing credentials. This Terraform module deploys a complete Boundary Enterprise environment on GCP including:

- **Controllers** - Boundary control plane on Compute Engine VMs
- **Workers** - Ingress and egress workers for session proxying
- **Cloud SQL PostgreSQL** - Database backend
- **Cloud KMS** - Encryption key management (root, worker, recovery, BSR keys)
- **GCS** - Session recording storage (BSR, optional)
- **Secret Manager** - License, TLS certs, and database credentials (auto-created)

The module is self-contained: a single `terraform apply` creates all prerequisites (secrets, TLS certificates, database password) and deploys the full infrastructure.

## Architecture

```
                              +---------------------------------------------+
                              |           INTERNET / CLIENTS                 |
                              +---------------------+------------------------+
                                                    |
                                                    v
+-----------------------------------------------------------------------------------+
|                                  GCP PROJECT                                       |
|  +-----------------------------------------------------------------------------+  |
|  |                            PUBLIC SUBNET                                     |  |
|  |                                                                              |  |
|  |   +----------------------------------------------------------------+        |  |
|  |   |              BOUNDARY CONTROL PLANE (HVD Controller)           |        |  |
|  |   |  +-----------+  +-----------+  +-----------+                   |        |  |
|  |   |  |Controller |  |Controller |  |Controller |  Port 9200 (API) |        |  |
|  |   |  |   VM 1    |  |   VM 2    |  |   VM 3    |  Port 9201 (Clust|er)     |  |
|  |   |  +-----------+  +-----------+  +-----------+                   |        |  |
|  |   |                        |                                       |        |  |
|  |   |              +---------+---------+                             |        |  |
|  |   |              |   Load Balancer   | <-- External/Internal       |        |  |
|  |   |              +-------------------+                             |        |  |
|  |   +----------------------------------------------------------------+        |  |
|  |                                                                              |  |
|  |   +--------------------------+                                               |  |
|  |   |  INGRESS WORKER (HVD)   |  Port 9202 (Proxy)                            |  |
|  |   |  +--------+ +--------+  | <-- Client Sessions                           |  |
|  |   |  |Worker 1| |Worker 2|  |                                               |  |
|  |   |  +--------+ +--------+  |                                               |  |
|  |   +------------+-------------+                                               |  |
|  |                |                                                             |  |
|  +----------------+-------------------------------------------------------------+  |
|                   |                                                                |
|  +----------------+-------------------------------------------------------------+  |
|  |                |              PRIVATE SUBNET                                  |  |
|  |                v                                                              |  |
|  |   +--------------------------+                                                |  |
|  |   |   EGRESS WORKER (HVD)   |                                                |  |
|  |   |  +--------+ +--------+  |                                                |  |
|  |   |  |Worker 1| |Worker 2|  |                                                |  |
|  |   |  +--------+ +--------+  |                                                |  |
|  |   +------------+-------------+                                                |  |
|  |                |                                                              |  |
|  |                v                                                              |  |
|  |   +---------+ +---------+ +---------+                                         |  |
|  |   | Target  | | Target  | | Target  |  SSH, RDP, K8s, Databases              |  |
|  |   |  Host   | |  Host   | |  Host   |                                        |  |
|  |   +---------+ +---------+ +---------+                                         |  |
|  +-------------------------------------------------------------------------------+  |
|                                                                                     |
|  +-------------------------------------------------------------------------------+  |
|  |                           GCP MANAGED SERVICES                                 |  |
|  |                                                                                |  |
|  |  +---------------+  +---------------+  +---------------+                       |  |
|  |  |   Cloud SQL   |  |   Cloud KMS   |  |Secret Manager |                       |  |
|  |  |  PostgreSQL   |  |               |  |               |                       |  |
|  |  |               |  |  - Root Key   |  |  - License    |                       |  |
|  |  |  - boundary   |  |  - Worker Key |  |  - TLS Cert   |                       |  |
|  |  |  - HA (Reg.)  |  |  - Recovery   |  |  - TLS Key    |                       |  |
|  |  |               |  |  - BSR Key    |  |  - DB Password|                       |  |
|  |  +---------------+  +---------------+  +---------------+                       |  |
|  |                                                                                |  |
|  |  +---------------+                                                             |  |
|  |  | Cloud Storage |  (Optional - Session Recording)                             |  |
|  |  |  GCS Bucket   |                                                             |  |
|  |  +---------------+                                                             |  |
|  +-------------------------------------------------------------------------------+  |
+-------------------------------------------------------------------------------------+
```

### Traffic Flow

1. **Client** connects to Boundary API/UI via Load Balancer (port 9200)
2. **Controller** authenticates user and authorizes session
3. **Client** connects to Ingress Worker (port 9202) for session
4. **Ingress Worker** proxies to Egress Worker (multi-hop) or directly to target
5. **Egress Worker** connects to target host (SSH, RDP, K8s, etc.)

---

## Prerequisites

1. **GCP Project** with billing enabled
2. **Boundary Enterprise License** (`boundary.hclic` file)
3. **Terraform** >= 1.3
4. **Packer** >= 1.9.0 (for building VM image)
5. **gcloud CLI** authenticated
6. **Private Service Access** configured on your VPC (required for Cloud SQL private IP connectivity)
7. **Required APIs enabled**:
   ```bash
   gcloud services enable \
     compute.googleapis.com \
     sqladmin.googleapis.com \
     cloudkms.googleapis.com \
     secretmanager.googleapis.com \
     servicenetworking.googleapis.com \
     iam.googleapis.com \
     dns.googleapis.com
   ```

---

## Quick Start

```bash
# Set your GCP project
export PROJECT_ID="your-gcp-project-id"

# 1. Build the Packer VM image (one-time)
make packer/build

# 2. Deploy Boundary infrastructure
make terraform/apply

# 3. Destroy when done
make terraform/destroy
```

---

## Step 1: Build the Packer VM Image

The Boundary VMs require a pre-built image with Boundary Enterprise installed. This image must be built in your GCP project before deploying.

### 1.1 Configure and Build

```bash
cd packer

export PROJECT_ID="your-gcp-project-id"
export ZONE="us-central1-a"

packer init boundary.pkr.hcl
packer build \
  -var "project_id=$PROJECT_ID" \
  -var "zone=$ZONE" \
  boundary.pkr.hcl
```

### 1.2 Verify the Image

```bash
gcloud compute images list --project=$PROJECT_ID --filter="family=boundary-enterprise"
```

Expected output:
```
NAME                                              PROJECT              FAMILY               STATUS
hashicorp-ubuntu2204-boundary-x86-64-v0210-XXXX   your-project-id      boundary-enterprise  READY
```

The module uses the image family `boundary-enterprise` by default, which automatically resolves to the latest image.

---

## Step 2: Deploy Boundary

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
boundary_fqdn     = "boundary.example.com"
license_file_path = "./boundary.hclic"

# Network
vpc_name               = "default"
controller_subnet_name = "default"

# Optional - TLS (leave unset for auto-generated self-signed certs)
# tls_cert_path      = "/path/to/cert.pem"
# tls_key_path       = "/path/to/key.pem"
# tls_ca_bundle_path = "/path/to/ca-bundle.pem"

# Optional - Sizing
# controller_instance_count     = 3
# ingress_worker_instance_count = 2
# deploy_ingress_worker         = true
# deploy_egress_worker          = true

# Optional - Load balancer (internal or external)
# api_load_balancing_scheme = "internal"

# Optional - Proxy subnet (set false if one already exists in your VPC/region)
# create_proxy_subnet = true
```

### 2.2 Deploy

```bash
terraform init
terraform apply -var-file=terraform.tfvars
```

The deployment automatically:
- Creates Secret Manager secrets for license, TLS certificates, and database password
- Generates self-signed TLS certificates (or uses your provided ones)
- Deploys Boundary controllers and workers
- Creates Cloud SQL PostgreSQL database
- Sets up Cloud KMS encryption keys
- Initializes the Boundary database via cloud-init

### 2.3 Get Outputs

```bash
terraform output boundary_url
terraform output controller_load_balancer_ip
terraform output post_deployment_instructions
```

---

## Access Boundary

After deployment, configure DNS to point `boundary_fqdn` to the controller load balancer IP:

```bash
# Get the load balancer IP
terraform output controller_load_balancer_ip
```

### External Load Balancer

If `api_load_balancing_scheme = "external"`, the API is reachable from anywhere:

```bash
# Verify the API is responding
curl -sk https://<LOAD_BALANCER_IP>:9200/v1/scopes

# Access the UI
open https://boundary.example.com:9200

# Authenticate via CLI
export BOUNDARY_ADDR="https://boundary.example.com:9200"
boundary authenticate
```

### Internal Load Balancer

If `api_load_balancing_scheme = "internal"` (default), the API is only reachable from within the VPC. SSH into a controller via IAP to verify:

```bash
# SSH to a controller and test the API
gcloud compute ssh <CONTROLLER_INSTANCE> \
  --project=$PROJECT_ID \
  --zone=<ZONE> \
  --tunnel-through-iap \
  -- "curl -sk https://127.0.0.1:9200/v1/scopes"

# Authenticate via API from inside the VPC
gcloud compute ssh <CONTROLLER_INSTANCE> \
  --project=$PROJECT_ID \
  --zone=<ZONE> \
  --tunnel-through-iap \
  -- "curl -sk -X POST 'https://127.0.0.1:9200/v1/auth-methods/<AUTH_METHOD_ID>:authenticate' \
       -d '{\"attributes\":{\"login_name\":\"admin\",\"password\":\"<PASSWORD>\"}}'"
```

To access the API or UI from your local machine with an internal LB, use an IAP TCP tunnel:

```bash
# Forward local port 9200 to the controller via IAP
gcloud compute start-iap-tunnel <CONTROLLER_INSTANCE> 9200 \
  --project=$PROJECT_ID \
  --zone=<ZONE> \
  --local-host-port=localhost:9200

# Then in another terminal:
export BOUNDARY_ADDR="https://localhost:9200"
boundary authenticate
```

### Retrieve Initial Admin Credentials

The first controller to boot runs `boundary database init`, which creates the initial admin user. The credentials are logged to `/var/log/boundary-cloud-init.log` on the winning controller.

```bash
# Find controller VMs
gcloud compute instances list --project=$PROJECT_ID --filter="name~boundary-controller"

# SSH to a controller via IAP and check for credentials
gcloud compute ssh <CONTROLLER_INSTANCE> \
  --project=$PROJECT_ID \
  --zone=<ZONE> \
  --tunnel-through-iap \
  -- "sudo grep -A7 'BOUNDARY INITIAL ADMIN CREDENTIALS' /var/log/boundary-cloud-init.log"
```

Expected output:
```
BOUNDARY INITIAL ADMIN CREDENTIALS
=============================================
  Auth Method ID: ampw_XXXXXXXXXXXX
  Login Name:     admin
  Password:       <generated-password>
=============================================
```

If credentials are not found on one controller, try another — only the controller that acquired the database lock will have them.

### SSH Access to Controllers (IAP Tunnel)

All controller VMs are accessible via Identity-Aware Proxy (IAP) tunneling. No public IP or VPN is required.

```bash
# SSH to a specific controller
gcloud compute ssh <CONTROLLER_INSTANCE> \
  --project=$PROJECT_ID \
  --zone=<ZONE> \
  --tunnel-through-iap

# Check Boundary service status
sudo systemctl status boundary

# View Boundary logs
sudo journalctl -u boundary -f

# View cloud-init log
sudo cat /var/log/boundary-cloud-init.log

# Check Boundary configuration
sudo cat /etc/boundary.d/controller.hcl
```

---

## Configuration Reference

### Required Variables

| Variable | Description |
|----------|-------------|
| `project_id` | GCP project ID |
| `region` | GCP region (e.g., `us-central1`) |
| `boundary_fqdn` | Fully qualified domain name for Boundary |
| `license_file_path` | Path to Boundary Enterprise license file (.hclic) |
| `vpc_name` | VPC network name |
| `controller_subnet_name` | Subnet name for controllers |

### TLS Variables (Optional)

| Variable | Default | Description |
|----------|---------|-------------|
| `tls_cert_path` | `null` | Path to TLS certificate PEM file (null = self-signed) |
| `tls_key_path` | `null` | Path to TLS private key PEM file (null = self-signed) |
| `tls_ca_bundle_path` | `null` | Path to CA bundle PEM file |

### Controller Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `controller_instance_count` | `3` | Number of controller instances |
| `controller_machine_type` | `n2-standard-4` | Controller VM machine type |
| `controller_disk_size_gb` | `50` | Boot disk size (GB) |
| `api_load_balancing_scheme` | `internal` | `internal` or `external` |

### Worker Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `deploy_ingress_worker` | `true` | Deploy ingress worker (public-facing) |
| `deploy_egress_worker` | `true` | Deploy egress worker (private) |
| `ingress_worker_instance_count` | `2` | Number of ingress workers |
| `egress_worker_instance_count` | `2` | Number of egress workers |
| `worker_machine_type` | `n2-standard-2` | Worker VM machine type |
| `worker_disk_size_gb` | `50` | Boot disk size (GB) |
| `enable_session_recording` | `false` | Enable BSR session recording |

### Network Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `worker_subnet_name` | `null` | Subnet for workers (defaults to controller subnet) |
| `vpc_project_id` | `null` | VPC project ID if different from deployment project |
| `create_proxy_subnet` | `true` | Create proxy-only subnet for internal LB |
| `proxy_subnet_cidr` | `192.168.100.0/23` | CIDR for proxy-only subnet |

### Database Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `postgres_version` | `POSTGRES_16` | Cloud SQL PostgreSQL version |
| `postgres_machine_type` | `db-custom-4-16384` | Cloud SQL instance tier |
| `postgres_disk_size` | `50` | Cloud SQL disk size (GB) |
| `postgres_availability_type` | `REGIONAL` | `REGIONAL` or `ZONAL` |

### DNS Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `create_cloud_dns_record` | `false` | Create Cloud DNS record for boundary_fqdn |
| `cloud_dns_managed_zone` | `null` | Cloud DNS managed zone name |

### Firewall Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `cidr_ingress_api_allow` | `["0.0.0.0/0"]` | CIDR ranges for API access (port 9200) |
| `cidr_ingress_worker_allow` | `["0.0.0.0/0"]` | CIDR ranges for worker access (port 9202) |
| `cidr_ingress_ssh_allow` | `["10.0.0.0/8"]` | CIDR ranges for SSH via IAP |

### Marketplace Variables (auto-populated)

| Variable | Default | Description |
|----------|---------|-------------|
| `boundary_image_family` | `boundary-enterprise` | VM image family |
| `boundary_image_project` | `null` | Image project (defaults to `project_id`) |
| `friendly_name_prefix` | `mp` | Resource name prefix (max 12 chars) |
| `goog_cm_deployment_name` | `""` | Marketplace deployment name |

### Outputs

| Output | Description |
|--------|-------------|
| `boundary_url` | Boundary API/UI URL |
| `boundary_fqdn` | FQDN for Boundary |
| `controller_load_balancer_ip` | Controller load balancer IP |
| `ingress_worker_lb_ip` | Ingress worker load balancer IP |
| `database_instance_id` | Cloud SQL instance ID |
| `database_private_ip` | Cloud SQL private IP |
| `key_ring_name` | Cloud KMS key ring name |
| `root_key_name` | Boundary root KMS key name |
| `worker_key_name` | Boundary worker KMS key name |
| `recovery_key_name` | Boundary recovery KMS key name |
| `bsr_bucket_name` | GCS bucket for session recording (if enabled) |
| `deployment_id` | Unique deployment identifier |
| `boundary_version` | Deployed Boundary version |
| `region` | Deployment region |
| `post_deployment_instructions` | Post-deployment setup guide |

---

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make packer/build` | Build Boundary VM image with Packer |
| `make packer/validate` | Validate Packer template |
| `make terraform/apply` | Deploy Boundary infrastructure |
| `make terraform/destroy` | Destroy all Boundary resources |
| `make terraform/plan` | Preview infrastructure changes |
| `make validate` | Run all validations (Terraform + CFT) |
| `make validate/full` | Full validation including terraform plan |
| `make package` | Create ZIP package for Marketplace |
| `make upload` | Upload package to GCS |
| `make release` | Full release pipeline (validate + package + upload) |
| `make image/list` | List available Boundary images |
| `make info` | Show configuration details |

---

## File Structure

```
products/boundary/
├── README.md                     # This file
├── CLAUDE.md                     # AI assistant guidance
├── Makefile                      # Build and deploy automation
├── boundary.hclic                # License file (gitignored)
├── .gitignore
│
├── main.tf                       # Root module (providers + prerequisites + infrastructure)
├── variables.tf                  # Input variables
├── outputs.tf                    # Output values
├── versions.tf                   # Provider versions
├── marketplace_test.tfvars       # Test/template configuration
│
├── metadata.yaml                 # GCP Marketplace blueprint metadata
├── metadata.display.yaml         # Marketplace UI configuration
│
├── packer/
│   ├── boundary.pkr.hcl          # Packer template for VM image
│   └── scripts/
│       └── install-boundary.sh   # Boundary installation script
│
└── modules/
    ├── controller/               # Controller HVD module (Cloud SQL, KMS, LB)
    ├── worker/                   # Worker HVD module (ingress/egress)
    └── prerequisites/            # Secret Manager secrets + TLS cert generation
```

### How It Works

```
terraform apply
    |
    v
module "prerequisites"          <-- Creates Secret Manager secrets
    |                               (license, TLS cert, TLS key, DB password)
    |                               Generates self-signed TLS if not provided
    v
module "controller"             <-- Deploys controller VMs, Cloud SQL, KMS, LB
    |                               Uses secret IDs from prerequisites
    v
module "ingress_worker"         <-- Deploys public-facing workers (optional)
    |                               KMS-based auth to controllers
    v
module "egress_worker"          <-- Deploys private workers (optional)
                                    Multi-hop through ingress workers
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

### Cleaning Up After Failed Destroy

```bash
# 1. Check remaining resources in state
terraform state list

# 2. Remove problematic resources from state (if already deleted in GCP)
terraform state rm <resource_address>

# 3. For Cloud SQL user deletion errors, delete the instance directly
gcloud sql instances delete <instance-name> --project=$PROJECT_ID --quiet

# 4. Clean up state files for fresh start
rm -f terraform.tfstate terraform.tfstate.backup
```

### Verify Cleanup

```bash
gcloud compute instances list --project=$PROJECT_ID --filter="name~boundary"
gcloud sql instances list --project=$PROJECT_ID --filter="name~boundary"
gcloud compute forwarding-rules list --project=$PROJECT_ID --filter="name~boundary"
```

---

## Troubleshooting

### Check Controller Logs

```bash
gcloud compute ssh <controller-instance> \
  --project=YOUR_PROJECT \
  --zone=us-central1-a \
  --tunnel-through-iap

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
| Controller not starting | Invalid license | Verify `license_file_path` points to valid `.hclic` |
| Workers not connecting | Network/firewall | Check firewall rules for port 9201 |
| Database connection failed | Cloud SQL not ready | Wait for Cloud SQL provisioning |
| Health check failing | Controllers initializing | Wait 5-10 minutes after deployment |
| Database URL parse error | Special chars in DB password | Fixed: `urlencode()` applied in `modules/controller/compute.tf` |
| `Error creating proxy-only subnet` | Org policy or existing subnet | Set `create_proxy_subnet = false` |
| Cloud SQL connection refused | No Private Service Access | Configure VPC peering for `servicenetworking.googleapis.com` |
| Packer: `Timeout waiting for SSH` | No firewall for `packer-build` tag | `gcloud compute firewall-rules create allow-packer-ssh --network=default --allow=tcp:22 --source-ranges=0.0.0.0/0 --target-tags=packer-build` |
| Cloud SQL: `no private services connection` | VPC missing PSA peering | `gcloud compute addresses create google-managed-services-default --global --purpose=VPC_PEERING --prefix-length=16 --network=default && gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com --ranges=google-managed-services-default --network=default` |

---

## Security Considerations

1. **License**: Stored in Secret Manager, not in code
2. **TLS**: Self-signed or user-provided certificates, all traffic encrypted
3. **KMS**: Separate Cloud KMS keys for root, worker, recovery, and BSR
4. **IAM**: Least-privilege service accounts per component
5. **Network**: Controllers and workers isolated in appropriate subnets
6. **Database Password**: Randomly generated (32 chars) and stored in Secret Manager

---

## Support

- [Boundary Documentation](https://developer.hashicorp.com/boundary/docs)
- [HashiCorp Support](https://support.hashicorp.com)
- [Boundary Community Forum](https://discuss.hashicorp.com/c/boundary)

## License

This deployment requires a valid HashiCorp Boundary Enterprise license.
