# images/vault/Dockerfile

FROM --platform=linux/amd64 hashicorp/vault:1.21

# Marketplace-required labels
LABEL com.google.cloud.marketplace.solution_id="vault"
LABEL com.google.cloud.marketplace.partner_id="hashicorp"
# Note: The com.googleapis.cloudmarketplace.product.service.name annotation
# must be added at build time via --annotation flag, not as a LABEL.
# The value is specific to your GCP Marketplace Partner Portal configuration.
# Example: services/vault-enterprise--1-16-ent.endpoints.ibm-software-mp-project-test.cloud.goog

# Add license files (required)
COPY LICENSE /usr/share/vault/LICENSE
COPY NOTICES /usr/share/vault/NOTICES

# Run as non-root (Marketplace requirement)
USER vault

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD vault status || exit 1
