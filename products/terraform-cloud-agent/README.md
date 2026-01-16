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
| `agentName` | Prefix for agent names | No (default: `gcp-agent`) |

## Build Commands

```bash
# Build all images
REGISTRY=gcr.io/$PROJECT_ID TAG=1.15.0 make app/build

# Run GCP Marketplace verification
REGISTRY=gcr.io/$PROJECT_ID TAG=1.15.0 make app/verify
```

## Directory Structure

```
products/terraform-cloud-agent/
├── Makefile                  # Build targets
├── schema.yaml               # GCP Marketplace schema (user inputs)
├── product.yaml              # Product metadata
├── manifest/
│   ├── application.yaml.template   # GCP Marketplace Application CRD
│   └── manifests.yaml.template     # Kubernetes resources
├── deployer/
│   └── Dockerfile            # Deployer image
├── apptest/
│   └── deployer/
│       └── Dockerfile        # Tester image
└── images/
    └── tfc-agent/
        └── Dockerfile        # TFC Agent image
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
