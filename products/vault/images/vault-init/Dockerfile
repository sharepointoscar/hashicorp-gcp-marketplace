# images/vault-init/Dockerfile
# HashiCorp Vault Enterprise - Init Container

ARG VAULT_VERSION=1.21.0

FROM --platform=linux/amd64 hashicorp/vault-enterprise:${VAULT_VERSION}-ent

# Patch OS-level CVEs (run as root before switching to vault user)
USER root
RUN apk update --no-cache && apk upgrade --no-cache openssl libcrypto3 libssl3

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
CMD ["echo 'Vault Enterprise init container ready'"]
