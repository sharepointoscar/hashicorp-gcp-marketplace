# HashiCorp Consul Enterprise for GCP Marketplace
#
# Uses public Docker Hub image: hashicorp/consul-enterprise
# Temporary: 1.22.4-ent Alpine image was pulled by HashiCorp, so we extract
# the Go 1.25.7 binary from the UBI variant and layer it onto the Alpine base.
#
# Build:
#   docker buildx build --platform linux/amd64 \
#     --build-arg CONSUL_VERSION=1.22.4 \
#     -t gcr.io/$PROJECT_ID/consul:TAG .

ARG CONSUL_VERSION=1.22.4

# Stage 1: Get the consul binary with Go 1.25.7 (CVE-2025-68121 fix)
FROM hashicorp/consul-enterprise:${CONSUL_VERSION}-ent-ubi AS binary-source

# Stage 2: Alpine base from latest available Alpine release (for filesystem/users/etc)
FROM hashicorp/consul-enterprise:1.22.3-ent

# Patch OS-level CVEs
# CVE-2025-15467: OpenSSL < 3.5.5
USER root
RUN apk update --no-cache && apk upgrade --no-cache openssl libcrypto3 libssl3

# Replace consul binary with 1.22.4 version (Go 1.25.7)
COPY --from=binary-source /bin/consul /bin/consul

USER consul

# GCP Marketplace service annotation is added via --annotation flag at build time

# Expose Consul ports
# 8500 - HTTP API and UI
# 8501 - HTTPS API
# 8502 - gRPC API
# 8503 - gRPC TLS API
# 8600 - DNS interface
# 8300 - Server RPC
# 8301 - Serf LAN (TCP/UDP)
# 8302 - Serf WAN (TCP/UDP)
EXPOSE 8500 8501 8502 8503 8600 8300 8301 8302

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD consul members || exit 1
