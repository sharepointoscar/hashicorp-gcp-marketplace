# Boundary Enterprise GCP Marketplace - Planning

## Context & Research Summary

### Architecture Analysis (from provided image)
- **Boundary Control Plane** - spans multiple AZs (public subnet)
- **Ingress Worker** - AZ1, public-facing
- **Egress Worker** - AZ1, private subnet
- **Target Hosts** - private subnet across AZs
- **External Dependencies**: KMS + PostgreSQL DB

### HashiCorp Validated Design (HVD) Modules
- `terraform-google-boundary-enterprise-controller-hvd` - Compute Engine VMs, Cloud SQL PostgreSQL, Cloud KMS, GCS for BSR
- `terraform-google-boundary-enterprise-worker-hvd` - Worker VMs (ingress/egress)
- **Architecture**: VM-based (NOT Kubernetes)

### GCP Marketplace Product Types
| Type | Description | Fit for Boundary |
|------|-------------|------------------|
| **VM Solutions** | Single/Multi-VM with Terraform/DM | ✅ Best match for HVD |
| **Kubernetes Apps** | Click-to-Deploy on GKE | ❌ Doesn't match HVD |
| **SaaS** | Hosted with integrated billing | ❌ Not applicable |

### Existing Monorepo Products Comparison
| Product | Architecture | Marketplace Type |
|---------|-------------|------------------|
| Vault | K8s StatefulSet + Raft | Kubernetes App |
| Consul | K8s StatefulSet + Raft | Kubernetes App |
| TFE | K8s + External Services | Kubernetes App |
| **Boundary** | VMs + Cloud SQL + KMS | **VM Solution** |

---

## Key Decision Point

**Boundary HVD uses VMs, not Kubernetes.** This creates a pattern mismatch with existing products in the monorepo.

### Options

1. **VM Solution (Terraform)** - Publish HVD modules to Marketplace
   - Pros: Matches official architecture, production-ready
   - Cons: Different pattern than Consul/Vault, more complex customer setup

2. **Kubernetes Adaptation** - Create new K8s manifests
   - Pros: Consistent with monorepo, simpler Click-to-Deploy
   - Cons: Deviates from official HVD, would need custom design

3. **Hybrid** - K8s for controller, guidance for workers
   - Pros: Partial K8s integration
   - Cons: Incomplete solution

---

## Decision: VM Solution with Terraform (Full Solution)

**Listing Type**: VM Solution
**Scope**: Full (Controllers + Workers + Cloud SQL + KMS)
**Deployment Method**: Terraform modules

---

## GCP Marketplace VM Solution Requirements

### Terraform Module Structure
- Custom modules allowed with approved providers only: `google`, `google-beta`, `random`, `time`, `tls`, `null`
- Must include `project_id` variable
- Must include `goog_cm_deployment_name` for UI deployment
- Image refs: `projects/PROJECT/global/images/IMAGE`

### Required Files
```
products/boundary/
├── metadata.yaml              # Blueprint metadata (CFT format)
├── metadata.display.yaml      # UI form customization
├── main.tf                    # Root module
├── variables.tf               # Input variables
├── outputs.tf                 # Outputs
├── versions.tf                # Provider versions
└── examples/
    └── marketplace_test/      # Test configuration
        └── marketplace_test.tfvars
```

### Testing & Validation
```bash
# Validate metadata
cft blueprint metadata -p . -v

# Test deployment
terraform plan -var project_id=$PROJECT -var-file marketplace_test.tfvars
```

---

## Implementation Plan

### Phase 1: Repository Structure
Create `products/boundary/` directory with VM Solution structure (differs from K8s products)

### Phase 2: Terraform Module
Wrap/adapt HVD modules for Marketplace:
- `terraform-google-boundary-enterprise-controller-hvd`
- `terraform-google-boundary-enterprise-worker-hvd`

### Phase 3: Marketplace Metadata
- `metadata.yaml` - Blueprint definition
- `metadata.display.yaml` - UI form (license, network, sizing)

### Phase 4: VM Images
- Build Boundary Enterprise VM image with Packer
- Include UBB agent for usage tracking
- Publish to project's Compute Engine images

### Phase 5: Testing & Submission
- Validate with CFT CLI
- Test via Producer Portal
- Submit for review

---

## Key Differences from K8s Products

| Aspect | Consul/Vault (K8s) | Boundary (VM) |
|--------|-------------------|---------------|
| Deployment | Click-to-Deploy | Terraform apply |
| Infrastructure | GKE cluster | Compute Engine VMs |
| Database | Raft PVC | Cloud SQL PostgreSQL |
| Images | Container images | VM images (Packer) |
| Metadata | schema.yaml | metadata.yaml (CFT) |

---

## Decisions Made

- ✅ **License**: User has Boundary Enterprise `.hclic` file
- ✅ **HVD Modules**: Fork/copy into monorepo (full control)
- ✅ **Version**: **0.21.0+ent** (latest stable; HVD default is 0.17.1+ent - will need update)

---

## Detailed Implementation Plan

### Step 1: Create Directory Structure
```
products/boundary/
├── CLAUDE.md                     # Product-specific guidance
├── README.md                     # Customer documentation
├── boundary.hclic                # Enterprise license (gitignored)
├── .gitignore
│
├── modules/                      # Forked HVD modules
│   ├── controller/               # From terraform-google-boundary-enterprise-controller-hvd
│   └── worker/                   # From terraform-google-boundary-enterprise-worker-hvd
│
├── main.tf                       # Root module (orchestrates controller + worker)
├── variables.tf                  # User inputs
├── outputs.tf                    # Deployment outputs
├── versions.tf                   # Provider constraints
│
├── metadata.yaml                 # GCP Marketplace blueprint metadata
├── metadata.display.yaml         # UI form customization
│
└── examples/
    └── marketplace_test/
        ├── main.tf
        └── marketplace_test.tfvars
```

### Step 2: Fork HVD Modules
Clone and adapt:
- `hashicorp/terraform-google-boundary-enterprise-controller-hvd`
- `hashicorp/terraform-google-boundary-enterprise-worker-hvd`

Adaptations needed:
- Add `goog_cm_deployment_name` variable for Marketplace
- Ensure only approved providers used
- Add Marketplace annotations to VM images

### Step 3: Create Root Module (main.tf)
Orchestrate full deployment:
```hcl
module "controller" {
  source = "./modules/controller"
  # ... controller config
}

module "ingress_worker" {
  source = "./modules/worker"
  create_lb = true  # Ingress worker
  # ... worker config
}

module "egress_worker" {
  source = "./modules/worker"
  create_lb = false  # Egress worker
  worker_is_internal = true
  # ... worker config
}
```

### Step 4: Create Marketplace Metadata

**metadata.yaml** (CFT Blueprint format):
```yaml
apiVersion: blueprints.cloud.google.com/v1alpha1
kind: BlueprintMetadata
metadata:
  name: boundary-enterprise
spec:
  info:
    title: HashiCorp Boundary Enterprise
    version: 0.17.1
    source:
      repo: https://github.com/hashicorp/...
    description: Secure remote access solution
  content:
    architecture:
      diagramUrl: https://...
    documentation:
      - title: Boundary Documentation
        url: https://developer.hashicorp.com/boundary
  interfaces:
    variables:
      - name: project_id
        description: GCP project ID
      - name: boundary_license
        description: Boundary Enterprise license
      - name: boundary_fqdn
        description: FQDN for Boundary
      # ... more variables
```

**metadata.display.yaml**:
```yaml
apiVersion: blueprints.cloud.google.com/v1alpha1
kind: BlueprintMetadata
metadata:
  name: boundary-enterprise-display
spec:
  ui:
    input:
      variables:
        project_id:
          name: project_id
          title: Project ID
        boundary_license:
          name: boundary_license
          title: Boundary Enterprise License
          section: licensing
          xGoogleProperty:
            type: ET_GCE_DISK_IMAGE  # Masked field
```

### Step 5: Validation Script
Create `products/boundary/scripts/validate.sh`:
```bash
#!/bin/bash
# Validate Boundary deployment

# 1. Validate metadata
cft blueprint metadata -p . -v

# 2. Test terraform plan
terraform init
terraform plan -var project_id=$PROJECT_ID \
  -var-file examples/marketplace_test/marketplace_test.tfvars

# 3. Optional: Full deployment test
terraform apply -auto-approve
# ... health checks ...
terraform destroy -auto-approve
```

### Step 6: Testing
```bash
cd products/boundary

# Place license file
cp /path/to/boundary.hclic .

# Validate metadata
cft blueprint metadata -p . -v

# Test plan
terraform plan \
  -var project_id=$PROJECT_ID \
  -var boundary_license="$(cat boundary.hclic)" \
  -var boundary_fqdn="boundary.example.com"

# Full deployment (optional)
terraform apply
```

---

## Files to Create

| File | Purpose |
|------|---------|
| `products/boundary/CLAUDE.md` | Product guidance |
| `products/boundary/main.tf` | Root orchestration module |
| `products/boundary/variables.tf` | Input variables |
| `products/boundary/outputs.tf` | Deployment outputs |
| `products/boundary/versions.tf` | Provider constraints |
| `products/boundary/metadata.yaml` | Marketplace blueprint |
| `products/boundary/metadata.display.yaml` | UI customization |
| `products/boundary/modules/controller/*` | Forked controller HVD |
| `products/boundary/modules/worker/*` | Forked worker HVD |
| `products/boundary/examples/marketplace_test/*` | Test configuration |

---

## Verification

1. **Metadata validation**: `cft blueprint metadata -p . -v`
2. **Terraform plan**: Succeeds with test variables
3. **Full deployment**: Creates all resources (controllers, workers, DB, KMS)
4. **Health checks**: Boundary API responds, workers connect
5. **Producer Portal**: Validation passes (up to 2 hours)

---

## Resolved Questions

1. **Boundary version**: Use **0.21.0+ent** (latest stable). HVD defaults to 0.17.1+ent but we'll update.
2. **VM images**: HVD uses **binary downloads** (not container images). Binaries fetched from releases.hashicorp.com during VM provisioning via cloud-init.
3. **License storage**: License stored in **GCP Secret Manager** (not embedded in images).

## Next Steps After Plan Approval

1. Fork HVD controller module from GitHub
2. Fork HVD worker module from GitHub
3. Update `boundary_version` default to `0.21.0+ent`
4. Create Marketplace metadata files
5. Create root orchestration module
6. Test with Boundary license file

---

## Files Created

- ✅ `products/boundary/README.md` - Usage and deployment documentation
- ✅ `products/boundary/boundary.hclic` - Enterprise license (user provided)
- ⏳ `products/boundary/CLAUDE.md` - AI assistant guidance (pending)
- ⏳ `products/boundary/.gitignore` - Git ignore patterns (pending)
- ⏳ `products/boundary/main.tf` - Root Terraform module (pending)
- ⏳ `products/boundary/variables.tf` - Input variables (pending)
- ⏳ `products/boundary/outputs.tf` - Output values (pending)
- ⏳ `products/boundary/versions.tf` - Provider versions (pending)
- ⏳ `products/boundary/modules/` - Forked HVD modules (pending)
