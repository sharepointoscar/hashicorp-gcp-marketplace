# images/vault-init/Dockerfile

FROM --platform=linux/amd64 hashicorp/vault:1.21

# Marketplace-required labels
LABEL com.google.cloud.marketplace.solution_id="vault"
LABEL com.google.cloud.marketplace.partner_id="hashicorp"
# Required as of January 2025 for GCP Marketplace
# Format: services/<solution-id>.mp-<partner-id>.appspot.com
LABEL com.googleapis.cloudmarketplace.product.service.name="services/vault.mp-hashicorp.appspot.com"

# This init container can be used for pre-flight checks or initialization
# Currently uses the same base as vault for consistency

USER vault

ENTRYPOINT ["/bin/sh", "-c"]
CMD ["echo 'Vault init container ready'"]
