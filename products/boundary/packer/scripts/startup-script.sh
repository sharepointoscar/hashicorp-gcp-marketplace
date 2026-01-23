#!/usr/bin/env bash
# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Boundary Enterprise Startup Script
# This script runs on VM boot to configure Boundary from instance metadata
#------------------------------------------------------------------------------

set -euo pipefail

LOGFILE="/var/log/boundary-startup.log"
BOUNDARY_DIR_CONFIG="/etc/boundary.d"
BOUNDARY_DIR_TLS="/etc/boundary.d/tls"
BOUNDARY_DIR_LICENSE="/opt/boundary/license"
BOUNDARY_USER="boundary"
BOUNDARY_GROUP="boundary"

log() {
  local level="$1"
  local message="$2"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "$timestamp [$level] $message" | tee -a "$LOGFILE"
}

get_metadata() {
  local key="$1"
  curl -sf -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/${key}" 2>/dev/null || echo ""
}

get_secret() {
  local secret_id="$1"
  gcloud secrets versions access latest --secret="$secret_id" 2>/dev/null
}

log "INFO" "Starting Boundary configuration..."

#------------------------------------------------------------------------------
# Get Instance Metadata
#------------------------------------------------------------------------------
VM_PRIVATE_IP=$(curl -sf -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
log "INFO" "VM Private IP: $VM_PRIVATE_IP"

# Required metadata
BOUNDARY_LICENSE_SECRET=$(get_metadata "boundary-license-secret")
BOUNDARY_TLS_CERT_SECRET=$(get_metadata "boundary-tls-cert-secret")
BOUNDARY_TLS_KEY_SECRET=$(get_metadata "boundary-tls-key-secret")
BOUNDARY_DATABASE_URL=$(get_metadata "boundary-database-url")
BOUNDARY_KMS_ROOT_KEY=$(get_metadata "boundary-kms-root-key")
BOUNDARY_KMS_RECOVERY_KEY=$(get_metadata "boundary-kms-recovery-key")
BOUNDARY_KMS_WORKER_KEY=$(get_metadata "boundary-kms-worker-key")
BOUNDARY_KMS_PROJECT=$(get_metadata "boundary-kms-project")
BOUNDARY_KMS_REGION=$(get_metadata "boundary-kms-region")
BOUNDARY_KMS_KEYRING=$(get_metadata "boundary-kms-keyring")

# Optional metadata
BOUNDARY_TLS_CA_SECRET=$(get_metadata "boundary-tls-ca-secret")
BOUNDARY_KMS_BSR_KEY=$(get_metadata "boundary-kms-bsr-key")
BOUNDARY_TLS_DISABLE=$(get_metadata "boundary-tls-disable")
BOUNDARY_ROLE=$(get_metadata "boundary-role")  # controller or worker

BOUNDARY_TLS_DISABLE="${BOUNDARY_TLS_DISABLE:-false}"
BOUNDARY_ROLE="${BOUNDARY_ROLE:-controller}"

log "INFO" "Boundary role: $BOUNDARY_ROLE"

#------------------------------------------------------------------------------
# Retrieve Secrets
#------------------------------------------------------------------------------
log "INFO" "Retrieving secrets from Secret Manager..."

# License
if [[ -n "$BOUNDARY_LICENSE_SECRET" ]]; then
  log "INFO" "Retrieving license..."
  get_secret "$BOUNDARY_LICENSE_SECRET" > "$BOUNDARY_DIR_LICENSE/license.hclic"
  chown $BOUNDARY_USER:$BOUNDARY_GROUP "$BOUNDARY_DIR_LICENSE/license.hclic"
  chmod 640 "$BOUNDARY_DIR_LICENSE/license.hclic"
fi

# TLS Certificate
if [[ -n "$BOUNDARY_TLS_CERT_SECRET" ]]; then
  log "INFO" "Retrieving TLS certificate..."
  get_secret "$BOUNDARY_TLS_CERT_SECRET" | base64 -d > "$BOUNDARY_DIR_TLS/cert.pem"
  chown $BOUNDARY_USER:$BOUNDARY_GROUP "$BOUNDARY_DIR_TLS/cert.pem"
  chmod 640 "$BOUNDARY_DIR_TLS/cert.pem"
fi

# TLS Private Key
if [[ -n "$BOUNDARY_TLS_KEY_SECRET" ]]; then
  log "INFO" "Retrieving TLS private key..."
  get_secret "$BOUNDARY_TLS_KEY_SECRET" | base64 -d > "$BOUNDARY_DIR_TLS/key.pem"
  chown $BOUNDARY_USER:$BOUNDARY_GROUP "$BOUNDARY_DIR_TLS/key.pem"
  chmod 640 "$BOUNDARY_DIR_TLS/key.pem"
fi

# TLS CA Bundle (optional)
if [[ -n "$BOUNDARY_TLS_CA_SECRET" ]]; then
  log "INFO" "Retrieving TLS CA bundle..."
  get_secret "$BOUNDARY_TLS_CA_SECRET" | base64 -d > "$BOUNDARY_DIR_TLS/ca.pem"
  chown $BOUNDARY_USER:$BOUNDARY_GROUP "$BOUNDARY_DIR_TLS/ca.pem"
  chmod 640 "$BOUNDARY_DIR_TLS/ca.pem"
fi

#------------------------------------------------------------------------------
# Generate Configuration
#------------------------------------------------------------------------------
log "INFO" "Generating Boundary configuration..."

HOSTNAME=$(hostname -s | tr '[:upper:]' '[:lower:]')

if [[ "$BOUNDARY_ROLE" == "controller" ]]; then
  # Controller configuration
  cat > "$BOUNDARY_DIR_CONFIG/boundary.hcl" <<EOF
disable_mlock = true

telemetry {
  prometheus_retention_time = "24h"
  disable_hostname          = true
}

controller {
  name        = "$HOSTNAME"
  description = "Boundary controller"

  database {
    url = "$BOUNDARY_DATABASE_URL"
  }

  license = "file:///$BOUNDARY_DIR_LICENSE/license.hclic"
}

listener "tcp" {
  address            = "0.0.0.0:9200"
  purpose            = "api"
  tls_disable        = $BOUNDARY_TLS_DISABLE
  tls_cert_file      = "$BOUNDARY_DIR_TLS/cert.pem"
  tls_key_file       = "$BOUNDARY_DIR_TLS/key.pem"
  cors_enabled       = true
  cors_allowed_origins = ["*"]
}

listener "tcp" {
  address = "$VM_PRIVATE_IP:9201"
  purpose = "cluster"
}

listener "tcp" {
  address       = "0.0.0.0:9203"
  purpose       = "ops"
  tls_disable   = $BOUNDARY_TLS_DISABLE
  tls_cert_file = "$BOUNDARY_DIR_TLS/cert.pem"
  tls_key_file  = "$BOUNDARY_DIR_TLS/key.pem"
}

kms "gcpckms" {
  purpose    = "root"
  project    = "$BOUNDARY_KMS_PROJECT"
  region     = "$BOUNDARY_KMS_REGION"
  key_ring   = "$BOUNDARY_KMS_KEYRING"
  crypto_key = "$BOUNDARY_KMS_ROOT_KEY"
}

kms "gcpckms" {
  purpose    = "recovery"
  project    = "$BOUNDARY_KMS_PROJECT"
  region     = "$BOUNDARY_KMS_REGION"
  key_ring   = "$BOUNDARY_KMS_KEYRING"
  crypto_key = "$BOUNDARY_KMS_RECOVERY_KEY"
}

kms "gcpckms" {
  purpose    = "worker-auth"
  project    = "$BOUNDARY_KMS_PROJECT"
  region     = "$BOUNDARY_KMS_REGION"
  key_ring   = "$BOUNDARY_KMS_KEYRING"
  crypto_key = "$BOUNDARY_KMS_WORKER_KEY"
}
EOF

  # Add BSR KMS if configured
  if [[ -n "$BOUNDARY_KMS_BSR_KEY" ]]; then
    cat >> "$BOUNDARY_DIR_CONFIG/boundary.hcl" <<EOF

kms "gcpckms" {
  purpose    = "bsr"
  project    = "$BOUNDARY_KMS_PROJECT"
  region     = "$BOUNDARY_KMS_REGION"
  key_ring   = "$BOUNDARY_KMS_KEYRING"
  crypto_key = "$BOUNDARY_KMS_BSR_KEY"
}
EOF
  fi

else
  # Worker configuration
  BOUNDARY_CONTROLLER_ADDR=$(get_metadata "boundary-controller-addr")
  BOUNDARY_WORKER_TYPE=$(get_metadata "boundary-worker-type")  # ingress or egress

  cat > "$BOUNDARY_DIR_CONFIG/boundary.hcl" <<EOF
disable_mlock = true

worker {
  name        = "$HOSTNAME"
  description = "Boundary ${BOUNDARY_WORKER_TYPE:-ingress} worker"

  initial_upstreams = ["$BOUNDARY_CONTROLLER_ADDR"]

  tags {
    type = ["${BOUNDARY_WORKER_TYPE:-ingress}"]
  }
}

listener "tcp" {
  address = "0.0.0.0:9202"
  purpose = "proxy"
}

kms "gcpckms" {
  purpose    = "worker-auth"
  project    = "$BOUNDARY_KMS_PROJECT"
  region     = "$BOUNDARY_KMS_REGION"
  key_ring   = "$BOUNDARY_KMS_KEYRING"
  crypto_key = "$BOUNDARY_KMS_WORKER_KEY"
}
EOF
fi

chown $BOUNDARY_USER:$BOUNDARY_GROUP "$BOUNDARY_DIR_CONFIG/boundary.hcl"
chmod 640 "$BOUNDARY_DIR_CONFIG/boundary.hcl"

#------------------------------------------------------------------------------
# Initialize Database (Controller only, first run)
#------------------------------------------------------------------------------
if [[ "$BOUNDARY_ROLE" == "controller" ]]; then
  log "INFO" "Checking if database initialization is needed..."

  # Try to initialize - will succeed on first controller, fail gracefully on others
  INIT_OUTPUT=$(/usr/bin/boundary database init -config "$BOUNDARY_DIR_CONFIG/boundary.hcl" 2>&1) || true

  if echo "$INIT_OUTPUT" | grep -q "Initial auth information"; then
    log "INFO" "Database initialized successfully!"

    # Extract and log credentials
    AUTH_METHOD_ID=$(echo "$INIT_OUTPUT" | grep "Auth Method ID:" | head -1 | awk '{print $NF}')
    LOGIN_NAME=$(echo "$INIT_OUTPUT" | grep "Login Name:" | head -1 | awk '{print $NF}')
    PASSWORD=$(echo "$INIT_OUTPUT" | grep "Password:" | head -1 | awk '{print $NF}')

    log "INFO" "==========================================="
    log "INFO" "BOUNDARY INITIAL ADMIN CREDENTIALS"
    log "INFO" "==========================================="
    log "INFO" "Auth Method ID: $AUTH_METHOD_ID"
    log "INFO" "Login Name:     $LOGIN_NAME"
    log "INFO" "Password:       $PASSWORD"
    log "INFO" "==========================================="
    log "INFO" "SAVE THESE CREDENTIALS SECURELY!"
    log "INFO" "==========================================="

  elif echo "$INIT_OUTPUT" | grep -q "already been initialized"; then
    log "INFO" "Database already initialized by another controller."
  else
    log "WARN" "Database init returned unexpected output - may need manual initialization"
  fi
fi

#------------------------------------------------------------------------------
# Start Boundary Service
#------------------------------------------------------------------------------
log "INFO" "Starting Boundary service..."
systemctl enable boundary
systemctl start boundary

# Wait for service to be ready
log "INFO" "Waiting for Boundary to be ready..."
sleep 10

if [[ "$BOUNDARY_ROLE" == "controller" ]]; then
  # Health check for controller
  for i in {1..30}; do
    if curl -ksfS --connect-timeout 5 "https://$VM_PRIVATE_IP:9203/health" &>/dev/null; then
      log "INFO" "Boundary controller is healthy!"
      break
    fi
    log "INFO" "Waiting for Boundary to become healthy... ($i/30)"
    sleep 10
  done
fi

log "INFO" "Boundary startup complete!"
