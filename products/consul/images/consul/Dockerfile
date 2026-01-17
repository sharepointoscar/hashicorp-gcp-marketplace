# HashiCorp Consul Enterprise for GCP Marketplace
#
# Uses public Docker Hub image: hashicorp/consul-enterprise
#
# Build:
#   docker buildx build --platform linux/amd64 \
#     --build-arg CONSUL_VERSION=1.22 \
#     -t gcr.io/$PROJECT_ID/consul:1.22 .

ARG CONSUL_VERSION=1.21

FROM hashicorp/consul-enterprise:${CONSUL_VERSION}-ent

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
