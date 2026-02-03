# HashiCorp Boundary Enterprise - GCP Marketplace Deployment Guide

Boundary Enterprise provides secure remote access to infrastructure without exposing networks or managing credentials. This package contains the Terraform modules and Packer templates to deploy Boundary Enterprise on GCP.

## Package Contents

    boundary-enterprise-0.21.0/
    ├── main.tf, variables.tf, outputs.tf, versions.tf   # Root Terraform module
    ├── metadata.yaml, metadata.display.yaml             # GCP Marketplace metadata
    ├── marketplace_test.tfvars                           # Example values for root module
    ├── boundary.hclic                                    # Enterprise license
    ├── deploy/                                           # Deployment wrapper (start here)
    │   ├── main.tf, variables.tf, outputs.tf, versions.tf
    │   ├── terraform.tfvars.example
    ├── modules/
    │   ├── prerequisites/     # Creates Secret Manager secrets + TLS certs
    │   ├── controller/        # Boundary control plane (VMs, Cloud SQL, KMS, LB)
    │   └── worker/            # Ingress/egress workers
    └── packer/
        ├── boundary.pkr.hcl   # Packer template for VM image
        └── scripts/
            ├── install-boundary.sh
            └── startup-script.sh

## Prerequisites

Before starting, ensure you have:

- **GCP Project** with billing enabled
- **Terraform** >= 1.3 installed
- **Packer** >= 1.9 installed
- **gcloud CLI** installed and authenticated
- **Boundary Enterprise license** (included as `boundary.hclic`)
- **VPC network** with at least one subnet (the `default` network works)
- **Private Service Access** configured on your VPC for Cloud SQL connectivity:
    ```
    gcloud compute addresses create google-managed-services-default \
      --global --purpose=VPC_PEERING --prefix-length=16 \
      --network=default --project=YOUR_PROJECT_ID

    gcloud services vpc-peerings connect \
      --service=servicenetworking.googleapis.com \
      --ranges=google-managed-services-default \
      --network=default --project=YOUR_PROJECT_ID
    ```

### Enable Required GCP APIs

    gcloud auth login
    gcloud config set project YOUR_PROJECT_ID

    gcloud services enable \
      compute.googleapis.com \
      sqladmin.googleapis.com \
      cloudkms.googleapis.com \
      secretmanager.googleapis.com \
      servicenetworking.googleapis.com \
      iam.googleapis.com \
      dns.googleapis.com

---

## Step 1: Extract the Package

    unzip boundary-enterprise-0.21.0.zip -d boundary-enterprise
    cd boundary-enterprise

---

## Step 2: Build the VM Image (Packer)

Boundary controllers and workers run on Compute Engine VMs that need a pre-built image with Boundary Enterprise installed.

    cd packer

    # Set your GCP project
    export PROJECT_ID="your-gcp-project-id"

    # Initialize Packer plugins
    packer init boundary.pkr.hcl

    # Validate the template
    packer validate \
      -var "project_id=$PROJECT_ID" \
      -var "zone=us-central1-a" \
      boundary.pkr.hcl

    # Build the image
    packer build \
      -var "project_id=$PROJECT_ID" \
      -var "zone=us-central1-a" \
      boundary.pkr.hcl

### Verify the Image

    gcloud compute images list \
      --project=$PROJECT_ID \
      --filter="family=boundary-enterprise"

Expected output:

    NAME                                              PROJECT           FAMILY               STATUS
    hashicorp-ubuntu2204-boundary-x86-64-v0210-XXXX   your-project      boundary-enterprise  READY

Return to the root directory:

    cd ..

---

## Step 3: Configure the Deployment

The `deploy/` directory is the recommended entry point. It automatically creates all prerequisite secrets (license, TLS certificates, database password) and deploys the full Boundary infrastructure.

    cd deploy

    # Copy the example variables file
    cp terraform.tfvars.example terraform.tfvars

Edit `terraform.tfvars` with your values:

    # terraform.tfvars

    #--- Required ---
    project_id        = "your-gcp-project-id"
    region            = "us-central1"
    boundary_fqdn     = "boundary.example.com"
    license_file_path = "../boundary.hclic"

    #--- Network ---
    vpc_name               = "default"
    controller_subnet_name = "default"

    #--- Sizing (optional, defaults shown) ---
    controller_instance_count     = 1
    ingress_worker_instance_count = 1
    deploy_ingress_worker         = true
    deploy_egress_worker          = false

    #--- Naming (optional) ---
    friendly_name_prefix = "bnd"

### Variable Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `project_id` | Yes | — | GCP project ID |
| `region` | No | `us-central1` | GCP region |
| `boundary_fqdn` | Yes | — | Fully qualified domain name for Boundary |
| `license_file_path` | Yes | — | Path to `.hclic` license file |
| `vpc_name` | Yes | — | Existing VPC network name |
| `controller_subnet_name` | Yes | — | Existing subnet name for controllers |
| `boundary_version` | No | `0.21.0+ent` | Boundary Enterprise version |
| `controller_instance_count` | No | `1` | Number of controller VMs |
| `controller_machine_type` | No | `n2-standard-4` | Controller VM machine type |
| `api_load_balancing_scheme` | No | `internal` | API load balancer: `internal` or `external` |
| `deploy_ingress_worker` | No | `true` | Deploy ingress workers |
| `deploy_egress_worker` | No | `false` | Deploy egress workers |
| `ingress_worker_instance_count` | No | `1` | Number of ingress workers |
| `egress_worker_instance_count` | No | `1` | Number of egress workers |
| `tls_cert_path` | No | `null` | Custom TLS cert (null = self-signed) |
| `tls_key_path` | No | `null` | Custom TLS key (null = self-signed) |
| `friendly_name_prefix` | No | `bnd` | Prefix for all resource names |

---

## Step 4: Deploy

    terraform init
    terraform apply

Terraform will:
1. Create Secret Manager secrets (license, TLS cert, TLS key, database password)
2. Generate self-signed TLS certificates (unless you provided your own)
3. Provision Cloud SQL PostgreSQL instance
4. Create Cloud KMS encryption keys (root, worker, recovery, BSR)
5. Deploy controller VM(s) with load balancer
6. Deploy ingress worker VM(s) with proxy load balancer (if enabled)
7. Deploy egress worker VM(s) (if enabled)

Review the plan and type `yes` to proceed.

> **Note**: Database initialization (`boundary database init`) runs **automatically** during the first controller VM boot via cloud-init. You do not need to run it manually. Initial admin credentials are logged to the controller's serial console output.

> **Timing**: The API should be available immediately after `terraform apply` completes. The managed instance group health check ensures controllers are healthy before Terraform finishes (~3-5 min for Cloud SQL provisioning + ~1 min for controller boot and database init).

---

## Step 5: Verify the Deployment

    # Get the Boundary URL
    terraform output boundary_url

    # Get the load balancer IP
    terraform output controller_load_balancer_ip

    # Get post-deployment instructions
    terraform output post_deployment_instructions

    # API health check (replace LB_IP with the actual IP)
    curl -sk https://LB_IP:9200/v1/scopes

---

## Step 6: Configure DNS and Access Boundary

1. **Configure DNS**: Create an A record pointing your `boundary_fqdn` to the controller load balancer IP.

2. **Access the UI**: Open `https://boundary.example.com:9200` in your browser.

3. **API access**: The API is available at the same URL (`https://boundary.example.com:9200`).

> **Note**: If using self-signed TLS certificates, your browser will show a security warning. This is expected for testing.

---

## Architecture

```
                              ┌─────────────────────────────────────────┐
                              │           INTERNET / CLIENTS            │
                              └──────────────────┬──────────────────────┘
                                                 │
                                                 ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│                                  GCP PROJECT                                    │
│  ┌──────────────────────────────────────────────────────────────────────────┐  │
│  │                            PUBLIC SUBNET                                  │  │
│  │                                                                           │  │
│  │   ┌─────────────────────────────────────────────────────────────────┐    │  │
│  │   │              BOUNDARY CONTROL PLANE (HVD Controller)            │    │  │
│  │   │  ┌───────────┐  ┌───────────┐  ┌───────────┐                    │    │  │
│  │   │  │Controller │  │Controller │  │Controller │   Port 9200 (API)  │    │  │
│  │   │  │   VM 1    │  │   VM 2    │  │   VM 3    │   Port 9201 (Cluster)   │  │
│  │   │  │  (AZ-a)   │  │  (AZ-b)   │  │  (AZ-c)   │                    │    │  │
│  │   │  └───────────┘  └───────────┘  └───────────┘                    │    │  │
│  │   │                        │                                         │    │  │
│  │   │              ┌─────────┴─────────┐                              │    │  │
│  │   │              │   Load Balancer   │◄──── External/Internal       │    │  │
│  │   │              └───────────────────┘                              │    │  │
│  │   └─────────────────────────────────────────────────────────────────┘    │  │
│  │                                                                           │  │
│  │   ┌──────────────────────────┐                                           │  │
│  │   │  INGRESS WORKER (HVD)   │                                            │  │
│  │   │  ┌────────┐ ┌────────┐  │   Port 9202 (Proxy)                       │  │
│  │   │  │Worker 1│ │Worker 2│  │◄──── Client Sessions                      │  │
│  │   │  └────────┘ └────────┘  │                                            │  │
│  │   └────────────┬─────────────┘                                           │  │
│  │                │                                                          │  │
│  └────────────────┼──────────────────────────────────────────────────────────┘  │
│                   │                                                              │
│  ┌────────────────┼──────────────────────────────────────────────────────────┐  │
│  │                │              PRIVATE SUBNET                               │  │
│  │                ▼                                                           │  │
│  │   ┌──────────────────────────┐                                            │  │
│  │   │   EGRESS WORKER (HVD)   │                                             │  │
│  │   │  ┌────────┐ ┌────────┐  │                                             │  │
│  │   │  │Worker 1│ │Worker 2│  │                                             │  │
│  │   │  └────────┘ └────────┘  │                                             │  │
│  │   └────────────┬─────────────┘                                            │  │
│  │                │                                                           │  │
│  │                ▼                                                           │  │
│  │   ┌─────────┐ ┌─────────┐ ┌─────────┐                                     │  │
│  │   │ Target  │ │ Target  │ │ Target  │  SSH, RDP, K8s, Databases           │  │
│  │   │  Host   │ │  Host   │ │  Host   │                                     │  │
│  │   └─────────┘ └─────────┘ └─────────┘                                     │  │
│  │                                                                            │  │
│  └────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                   │
│  ┌──────────────────────────────────────────────────────────────────────────────┐│
│  │                           GCP MANAGED SERVICES                                ││
│  │                                                                               ││
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐               ││
│  │  │   Cloud SQL     │  │    Cloud KMS    │  │ Secret Manager  │               ││
│  │  │   PostgreSQL    │  │                 │  │                 │               ││
│  │  │                 │  │  • Root Key     │  │  • License      │               ││
│  │  │  • boundary DB  │  │  • Worker Key   │  │  • TLS Cert     │               ││
│  │  │  • HA (Regional)│  │  • Recovery Key │  │  • TLS Key      │               ││
│  │  │                 │  │  • BSR Key      │  │  • DB Password  │               ││
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘               ││
│  │                                                                               ││
│  │  ┌─────────────────┐                                                         ││
│  │  │   Cloud Storage │  (Optional - Session Recording)                         ││
│  │  │   GCS Bucket    │                                                         ││
│  │  └─────────────────┘                                                         ││
│  └──────────────────────────────────────────────────────────────────────────────┘│
└───────────────────────────────────────────────────────────────────────────────────┘
```

### Traffic Flow

1. **Client** connects to Boundary API/UI via Load Balancer (port 9200)
2. **Controller** authenticates user and authorizes session
3. **Client** connects to Ingress Worker (port 9202) for session
4. **Ingress Worker** proxies to Egress Worker (multi-hop) or directly to target
5. **Egress Worker** connects to target host (SSH, RDP, K8s, etc.)

---

## Destroying Resources

From the `deploy/` directory:

    cd deploy
    terraform destroy

Review the plan and type `yes` to confirm.

### If Destroy Fails

If `terraform destroy` fails (e.g., Cloud SQL user deletion error):

    # Check remaining resources
    terraform state list

    # Remove problematic resources from state (if already deleted in GCP)
    terraform state rm <resource_address>

    # For Cloud SQL deletion errors
    gcloud sql instances delete <instance-name> --project=$PROJECT_ID --quiet

    # Clean up for fresh start
    rm -f terraform.tfstate terraform.tfstate.backup

---

## Troubleshooting

### Check Controller Logs

    gcloud compute ssh <controller-instance> \
      --project=YOUR_PROJECT \
      --zone=us-central1-a \
      --tunnel-through-iap

    sudo journalctl -u boundary -f

### Check Worker Logs

    gcloud compute ssh <worker-instance> \
      --project=YOUR_PROJECT \
      --zone=us-central1-a \
      --tunnel-through-iap

    sudo journalctl -u boundary -f

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Controller not starting | Invalid license | Verify `boundary.hclic` is valid |
| Workers not connecting | Firewall rules | Check firewall rules for port 9201 |
| Database connection failed | Cloud SQL provisioning | Wait for Cloud SQL to finish provisioning |
| Health check failing | Controllers initializing | Wait after deployment for controllers to start |
| Database URL parse error | Special characters in DB password | Fixed: `urlencode()` is applied to the DB password in `compute.tf` |
| `Error creating proxy-only subnet` | Org policy or existing subnet | Set `create_proxy_subnet = false` in root module if your VPC already has one |
| Cloud SQL connection refused | No Private Service Access | Configure VPC peering for `servicenetworking.googleapis.com` (see Prerequisites) |
| Packer build fails with GPG error | Stale apt cache | The install script handles this automatically |
| Packer build: `Timeout waiting for SSH` | No firewall rule allowing SSH (port 22) to `packer-build` tagged instances | Create rule: `gcloud compute firewall-rules create allow-packer-ssh --network=default --allow=tcp:22 --source-ranges=0.0.0.0/0 --target-tags=packer-build` |
| Cloud SQL: `network doesn't have at least 1 private services connection` | VPC missing Private Service Access peering | Create peering: `gcloud compute addresses create google-managed-services-default --global --purpose=VPC_PEERING --prefix-length=16 --network=default` then `gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com --ranges=google-managed-services-default --network=default` |

---

## Security Considerations

1. **License**: Stored in GCP Secret Manager, not in plaintext
2. **TLS**: All communication encrypted (self-signed or provided certificates)
3. **KMS**: Encryption keys managed by Cloud KMS
4. **IAM**: Least-privilege service accounts for each component
5. **Network**: Controllers and workers isolated in appropriate subnets
6. **Database Password**: Randomly generated and stored in Secret Manager

---

## Support

- [Boundary Documentation](https://developer.hashicorp.com/boundary/docs)
- [HashiCorp Support](https://support.hashicorp.com)

## License

This deployment requires a valid HashiCorp Boundary Enterprise license.
