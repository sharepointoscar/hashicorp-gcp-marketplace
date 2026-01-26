# images/ubbagent/Dockerfile
# UBB Agent for GCP Marketplace usage-based billing
#
# Uses Google's official ubbagent image as base and adds envsubst for
# environment variable expansion in config files.

FROM gcr.io/cloud-marketplace-tools/metering/ubbagent:0.2.4

USER root

# Install gettext for envsubst (used to expand env vars in config)
# Base image is Alpine-based
RUN apk add --no-cache gettext

# Create entrypoint script that:
# 1. Expands environment variables in the config file using envsubst
# 2. Starts ubbagent with the expanded config
RUN cat > /entrypoint.sh << 'SCRIPT'
#!/bin/sh
set -e

CONFIG_TEMPLATE="${AGENT_CONFIG_FILE:-/etc/ubbagent/config.yaml}"
CONFIG_EXPANDED="/tmp/ubbagent-config.yaml"

# Expand environment variables in config template
envsubst < "$CONFIG_TEMPLATE" > "$CONFIG_EXPANDED"

# Start ubbagent with expanded config
exec /ubbagent \
  --config "$CONFIG_EXPANDED" \
  --local-port "${AGENT_LOCAL_PORT:-4567}" \
  --state-dir "${AGENT_STATE_DIR:-/var/lib/ubbagent}" \
  --logtostderr
SCRIPT
RUN chmod +x /entrypoint.sh

# Create state directory
RUN mkdir -p /var/lib/ubbagent

ENTRYPOINT ["/entrypoint.sh"]
