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
# TFE 1.1.x requires: GKE 1.33, PostgreSQL 13+, Redis 7.x
ARG TFE_VERSION=1.1.3

# Use official HashiCorp Terraform Enterprise image
FROM images.releases.hashicorp.com/hashicorp/terraform-enterprise:${TFE_VERSION}

# Labels for GCP Marketplace
LABEL maintainer="HashiCorp <support@hashicorp.com>"
LABEL version="${TFE_VERSION}"
LABEL description="Terraform Enterprise for GCP Marketplace (External Services)"
LABEL com.hashicorp.product="terraform-enterprise"
LABEL com.hashicorp.operational-mode="active-active"

# The base image already includes:
# - Terraform Enterprise application
# - Vault for secrets management
# - Required runtime dependencies
# External services mode requires:
# - Cloud SQL PostgreSQL
# - Memorystore Redis
# - GCS bucket for object storage

# Fix CVE-2025-49844: redis vulnerability
# Upgrade redis packages to patched version
# Then fix permissions so terraform-enterprise user can read config templates
# Note: apt-get sets /etc/redis to drwxrws--- (redis:redis), blocking other users
USER root
RUN apt-get update && \
    apt-get install -y --only-upgrade redis-server redis-tools && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    chmod o+rx /etc/redis && \
    chmod -R a+r /etc/redis

# Switch back to non-root user (required by base image)
USER terraform-enterprise

# TFE runs its own process management
# Default entrypoint handles startup
