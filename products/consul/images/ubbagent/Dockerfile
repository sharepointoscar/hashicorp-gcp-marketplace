# images/ubbagent/Dockerfile
# Custom UBB Agent with patched golang.org/x/crypto vulnerability (CVE-2024-45337)
#
# This builds the ubbagent from source with updated dependencies to fix
# security vulnerabilities in the official Google image.

# Build stage
FROM golang:1.23-alpine AS builder

# Install git for cloning
RUN apk add --no-cache git

# Clone the ubbagent repository
WORKDIR /src
RUN git clone --depth 1 https://github.com/GoogleCloudPlatform/ubbagent.git .

# Update vulnerable dependencies
# CVE-2024-45337: golang.org/x/crypto < 0.31.0
RUN go get golang.org/x/crypto@v0.31.0 && \
    go mod tidy

# Build the agent
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /ubbagent .

# Runtime stage - use Alpine for shell support
FROM alpine:3.20

# Install gettext for envsubst
RUN apk add --no-cache gettext

# Copy the built binary
COPY --from=builder /ubbagent /ubbagent

# Create entrypoint script
RUN cat > /entrypoint.sh << 'SCRIPT'
#!/bin/sh
set -e

CONFIG_TEMPLATE="${AGENT_CONFIG_FILE:-/etc/ubbagent/config.yaml}"
CONFIG_EXPANDED="/tmp/ubbagent-config.yaml"

# Expand environment variables in config template
envsubst < "$CONFIG_TEMPLATE" > "$CONFIG_EXPANDED"

# Start ubbagent with expanded config
exec /ubbagent \
  -config "$CONFIG_EXPANDED" \
  -local-port "${AGENT_LOCAL_PORT:-4567}" \
  -state-dir "${AGENT_STATE_DIR:-/var/lib/ubbagent}" \
  -logtostderr
SCRIPT
RUN chmod +x /entrypoint.sh

# Create state directory
RUN mkdir -p /var/lib/ubbagent

# Run as non-root
RUN adduser -D -u 1000 ubbagent
USER ubbagent

ENTRYPOINT ["/entrypoint.sh"]
