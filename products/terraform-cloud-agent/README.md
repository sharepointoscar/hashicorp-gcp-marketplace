# HashiCorp Terraform Cloud Agent - GCP Marketplace

Terraform Cloud Agent is a lightweight process that executes Terraform runs on behalf of Terraform Cloud or Terraform Enterprise. Deploy agents in your GCP environment to enable Terraform Cloud to manage resources in private networks without exposing them to the internet.

## Overview

| Property | Value |
|----------|-------|
| **Product** | Terraform Cloud Agent |
| **Version** | 1.15.0 |
| **Model** | Click-to-Deploy |
| **Partner ID** | hashicorp |
| **Solution ID** | terraform-cloud-agent |

## Use Cases

- **Private Network Access**: Run Terraform operations on resources in private VPCs without opening inbound firewall rules
- **On-Premises Integration**: Connect on-premises infrastructure to Terraform Cloud
- **Compliance**: Keep Terraform execution within your network boundary for regulatory compliance
- **Air-Gapped Environments**: Execute Terraform in environments with restricted internet access

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Google Cloud                            │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                   GKE Cluster                         │  │
│  │  ┌─────────────────┐  ┌─────────────────┐            │  │
│  │  │  TFC Agent Pod  │  │  TFC Agent Pod  │  ...       │  │
│  │  │  ┌───────────┐  │  │  ┌───────────┐  │            │  │
│  │  │  │ tfc-agent │  │  │  │ tfc-agent │  │            │  │
│  │  │  └───────────┘  │  │  └───────────┘  │            │  │
│  │  │  ┌───────────┐  │  │  ┌───────────┐  │            │  │
│  │  │  │ ubbagent  │  │  │  │ ubbagent  │  │            │  │
│  │  │  └───────────┘  │  │  └───────────┘  │            │  │
│  │  └─────────────────┘  └─────────────────┘            │  │
│  └───────────────────────────────────────────────────────┘  │
│                            │                                │
│                            │ Outbound HTTPS (443)           │
└────────────────────────────┼────────────────────────────────┘
                             │
                             ▼
                   ┌─────────────────┐
                   │ Terraform Cloud │
                   │       or        │
                   │ Terraform Ent.  │
                   └─────────────────┘
```

## Prerequisites

1. **GKE Cluster**: A running GKE cluster where agents will be deployed
2. **Terraform Cloud/Enterprise Account**: Access to create agent pools
3. **Agent Pool Token**: Generated from Terraform Cloud/Enterprise agent pool settings

## Configuration Parameters

| Parameter | Description | Required |
|-----------|-------------|----------|
| `name` | Application instance name | Yes |
| `namespace` | Kubernetes namespace for deployment | Yes |
| `replicas` | Number of agent pods (1-10) | Yes |
| `agentToken` | Agent pool token from TFC/TFE | Yes |
| `reportingSecret` | GCP Marketplace reporting secret for billing | Yes |
| `agentName` | Prefix for agent names | No (default: `gcp-agent`) |
| `tfcAgentServiceAccount` | Service account for TFC Agent pods | No (auto-created) |

## Build and Validation

The standard validation workflow uses the shared `validate-marketplace.sh` script, which runs the full pipeline: prerequisites check, image builds, schema verification, mpdev install, mpdev verify, and vulnerability scan.

```bash
# Standard validation workflow (recommended)
REGISTRY=us-docker.pkg.dev/$PROJECT_ID/tfc-agent-marketplace TAG=1.15.0 \
  ./shared/scripts/validate-marketplace.sh terraform-cloud-agent

# Build only (from product directory)
cd products/terraform-cloud-agent
REGISTRY=us-docker.pkg.dev/$PROJECT_ID/tfc-agent-marketplace TAG=1.15.0 \
  MP_SERVICE_NAME="services/terraform-cloud-agent.endpoints.$PROJECT_ID.cloud.goog" \
  make app/build

# Run mpdev verify only (from product directory)
REGISTRY=us-docker.pkg.dev/$PROJECT_ID/tfc-agent-marketplace TAG=1.15.0 \
  make app/verify

# Run mpdev install only (from product directory)
REGISTRY=us-docker.pkg.dev/$PROJECT_ID/tfc-agent-marketplace TAG=1.15.0 \
  make app/install

# Cleanup test namespaces
./shared/scripts/validate-marketplace.sh terraform-cloud-agent --cleanup
```

**Environment variables:**

| Variable | Description |
|----------|-------------|
| `REGISTRY` | Artifact Registry path (e.g., `us-docker.pkg.dev/$PROJECT_ID/tfc-agent-marketplace`) |
| `TAG` | Image version tag (must match `schema.yaml` `publishedVersion`) |
| `MP_SERVICE_NAME` | GCP Marketplace service annotation (required for image builds) |
| `PROJECT_ID` | GCP project ID |

## Directory Structure

```
products/terraform-cloud-agent/
├── Makefile                          # Build targets (app/build, includes shared Makefiles)
├── schema.yaml                       # GCP Marketplace schema (user inputs)
├── product.yaml                      # Product metadata (id, version, partnerId, solutionId)
├── README.md                         # This file
├── manifest/
│   ├── application.yaml.template     # GCP Marketplace Application CRD
│   └── manifests.yaml.template       # Kubernetes resources (Deployment, Secret, ConfigMap)
├── deployer/
│   └── Dockerfile                    # Deployer image (envsubst-based)
├── apptest/
│   └── deployer/
│       ├── Dockerfile                # Tester deployer image
│       ├── schema.yaml               # Test schema with default values
│       └── manifest/
│           └── tester.yaml.template  # Verification test pod (10 tests)
└── images/
    └── tfc-agent/
        └── Dockerfile                # TFC Agent image (based on hashicorp/tfc-agent)
```

## Creating an Agent Pool Token

1. Log in to Terraform Cloud or Terraform Enterprise
2. Navigate to **Organization Settings** > **Agents**
3. Click **Create agent pool**
4. Give the pool a name (e.g., `gcp-marketplace-pool`)
5. Click **Create agent pool**
6. Click **Create token** and copy the token value
7. Use this token as the `agentToken` parameter during deployment

## Resources

- [Terraform Cloud Agents Documentation](https://developer.hashicorp.com/terraform/cloud-docs/agents)
- [Agent Pool Management](https://developer.hashicorp.com/terraform/cloud-docs/agents/agent-pools)
- [GCP Marketplace](https://console.cloud.google.com/marketplace)
