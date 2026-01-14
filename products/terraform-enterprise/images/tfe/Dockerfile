# images/tfe/Dockerfile
# HashiCorp Terraform Enterprise for GCP Marketplace
#
# NOTE: This Dockerfile wraps the official TFE image which requires
# authentication using your TFE license key:
#   Username: terraform
#   Password: <YOUR_TFE_LICENSE_KEY>
#
# The actual TFE image is pulled at deployment time using imagePullSecrets
# created from the user's license key.

# Build argument for TFE version
ARG TFE_VERSION=v202501-1

# Use official HashiCorp Terraform Enterprise image
FROM images.releases.hashicorp.com/hashicorp/terraform-enterprise:${TFE_VERSION}

# Labels for GCP Marketplace
LABEL maintainer="HashiCorp <support@hashicorp.com>"
LABEL version="${TFE_VERSION}"
LABEL description="Terraform Enterprise for GCP Marketplace"
LABEL com.hashicorp.product="terraform-enterprise"
LABEL com.hashicorp.operational-mode="disk"

# The base image already includes:
# - Terraform Enterprise application
# - Embedded PostgreSQL (for disk mode)
# - Embedded object storage (for disk mode)
# - Vault for secrets management
# - Required runtime dependencies

# TFE runs its own process management
# Default entrypoint handles startup
