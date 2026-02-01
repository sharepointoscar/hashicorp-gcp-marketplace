#!/usr/bin/env bash
# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Install Boundary Enterprise for GCP Marketplace VM Image
# This script is run by Packer during image creation
#------------------------------------------------------------------------------

set -euo pipefail

BOUNDARY_VERSION="${BOUNDARY_VERSION:-0.21.0+ent}"
BOUNDARY_DIR_BIN="/usr/bin"
BOUNDARY_DIR_CONFIG="/etc/boundary.d"
BOUNDARY_DIR_DATA="/opt/boundary/data"
BOUNDARY_DIR_TLS="/etc/boundary.d/tls"
BOUNDARY_DIR_LICENSE="/opt/boundary/license"
BOUNDARY_DIR_LOGS="/var/log/boundary"
BOUNDARY_USER="boundary"
BOUNDARY_GROUP="boundary"

echo "=== Installing Boundary Enterprise ${BOUNDARY_VERSION} ==="

#------------------------------------------------------------------------------
# Install Prerequisites
#------------------------------------------------------------------------------
echo "Installing prerequisites..."
export DEBIAN_FRONTEND=noninteractive

# Refresh apt keyrings to fix GPG signature errors on GCP Ubuntu images
apt-get clean
rm -rf /var/lib/apt/lists/*
apt-get update -y
apt-get install -y \
  jq \
  unzip \
  curl \
  ca-certificates \
  gnupg \
  lsb-release

# Install Google Cloud SDK if not present
if ! command -v gcloud &> /dev/null; then
  echo "Installing Google Cloud SDK..."
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
    tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
  apt-get update -y
  apt-get install -y google-cloud-sdk
fi

#------------------------------------------------------------------------------
# Create Boundary User and Group
#------------------------------------------------------------------------------
echo "Creating Boundary user and group..."
groupadd --system ${BOUNDARY_GROUP} || true
useradd --system --no-create-home -d ${BOUNDARY_DIR_CONFIG} -g ${BOUNDARY_GROUP} ${BOUNDARY_USER} || true

#------------------------------------------------------------------------------
# Create Directories
#------------------------------------------------------------------------------
echo "Creating directories..."
mkdir -p ${BOUNDARY_DIR_CONFIG}
mkdir -p ${BOUNDARY_DIR_DATA}
mkdir -p ${BOUNDARY_DIR_TLS}
mkdir -p ${BOUNDARY_DIR_LICENSE}
mkdir -p ${BOUNDARY_DIR_LOGS}
mkdir -p /opt/boundary

chown ${BOUNDARY_USER}:${BOUNDARY_GROUP} ${BOUNDARY_DIR_CONFIG}
chown ${BOUNDARY_USER}:${BOUNDARY_GROUP} ${BOUNDARY_DIR_DATA}
chown ${BOUNDARY_USER}:${BOUNDARY_GROUP} ${BOUNDARY_DIR_TLS}
chown ${BOUNDARY_USER}:${BOUNDARY_GROUP} ${BOUNDARY_DIR_LICENSE}
chown ${BOUNDARY_USER}:${BOUNDARY_GROUP} ${BOUNDARY_DIR_LOGS}
chown ${BOUNDARY_USER}:${BOUNDARY_GROUP} /opt/boundary

chmod 750 ${BOUNDARY_DIR_CONFIG}
chmod 750 ${BOUNDARY_DIR_DATA}
chmod 750 ${BOUNDARY_DIR_TLS}
chmod 750 ${BOUNDARY_DIR_LICENSE}
chmod 750 ${BOUNDARY_DIR_LOGS}

#------------------------------------------------------------------------------
# Download and Install Boundary Binary
#------------------------------------------------------------------------------
echo "Downloading Boundary Enterprise ${BOUNDARY_VERSION}..."
BOUNDARY_INSTALL_URL="https://releases.hashicorp.com/boundary/${BOUNDARY_VERSION}/boundary_${BOUNDARY_VERSION}_linux_amd64.zip"

curl -so /tmp/boundary.zip "${BOUNDARY_INSTALL_URL}"
unzip -o /tmp/boundary.zip boundary -d ${BOUNDARY_DIR_BIN}
rm /tmp/boundary.zip

# Set permissions
chmod 755 ${BOUNDARY_DIR_BIN}/boundary
chown root:root ${BOUNDARY_DIR_BIN}/boundary

# Verify installation
${BOUNDARY_DIR_BIN}/boundary version

#------------------------------------------------------------------------------
# Create Systemd Service (template - will be configured at runtime)
#------------------------------------------------------------------------------
echo "Creating systemd service..."
cat > /etc/systemd/system/boundary.service <<EOF
[Unit]
Description="HashiCorp Boundary"
Documentation=https://www.boundaryproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=${BOUNDARY_DIR_CONFIG}/boundary.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
User=${BOUNDARY_USER}
Group=${BOUNDARY_GROUP}
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=${BOUNDARY_DIR_BIN}/boundary server -config=${BOUNDARY_DIR_CONFIG}/boundary.hcl
ExecReload=/bin/kill --signal HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/boundary.service
systemctl daemon-reload

#------------------------------------------------------------------------------
# Create version file for reference
#------------------------------------------------------------------------------
echo "${BOUNDARY_VERSION}" > /opt/boundary/version

echo "=== Boundary Enterprise ${BOUNDARY_VERSION} installation complete ==="
