# images/tfc-agent/Dockerfile
# HashiCorp Terraform Cloud Agent for GCP Marketplace

# Use official HashiCorp TFC Agent image as base
FROM hashicorp/tfc-agent:1.15.0

# Labels for GCP Marketplace
LABEL maintainer="HashiCorp <support@hashicorp.com>"
LABEL version="1.15.0"
LABEL description="Terraform Cloud Agent for GCP Marketplace"

# The base image already includes:
# - tfc-agent binary
# - Required runtime dependencies
# - Non-root user configuration

# Agent runs as non-root user (already configured in base image)
# Default entrypoint is the tfc-agent binary
