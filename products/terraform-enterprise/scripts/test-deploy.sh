#!/bin/bash
# scripts/test-deploy.sh
# Test full TFE deployment on existing cluster before Partner Portal submission

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "=== TFE GCP Marketplace - Local Test Deployment ==="
echo ""

#=============================================================================
# Step 1: Repackage and upload all artifacts (Helm chart + TF module)
#=============================================================================
echo "=== Repackaging Artifacts ==="
echo ""

# Repackage Helm chart and push to Artifact Registry
echo "Pushing Helm chart..."
make helm/push

# Add minor version tags (required by GCP Marketplace)
echo "Adding minor version tags..."
make tags/minor

# Repackage and upload Terraform module to GCS
echo "Uploading Terraform module..."
make terraform/upload

echo ""
echo "=== Artifacts Updated ==="
echo ""

#=============================================================================
# Step 2: Check prerequisites
#=============================================================================

# Check for license file
LICENSE_FILE="terraform exp Mar 31 2026.hclic"
if [ ! -f "$LICENSE_FILE" ]; then
    echo "ERROR: License file not found: $LICENSE_FILE"
    exit 1
fi

# Check for certificates
CERT_DIR="terraform/certs"
if [ ! -f "$CERT_DIR/tfe.crt" ] || [ ! -f "$CERT_DIR/tfe.key" ]; then
    echo "ERROR: TLS certificates not found in $CERT_DIR"
    exit 1
fi

echo "License file: $LICENSE_FILE"
echo "Certificates: $CERT_DIR"
echo ""

# Base64 encode certificates
TLS_CERT=$(base64 < "$CERT_DIR/tfe.crt")
TLS_KEY=$(base64 < "$CERT_DIR/tfe.key")
CA_CERT=$(base64 < "$CERT_DIR/ca-bundle.pem")

# Read license
TFE_LICENSE=$(cat "$LICENSE_FILE")

# Generate encryption password if not set
ENCRYPTION_PASSWORD="${TFE_ENCRYPTION_PASSWORD:-$(openssl rand -base64 24)}"

echo "=== Configuration ==="
echo "Project:      ibm-software-mp-project-test"
echo "Cluster:      vault-mp-test (us-central1)"
echo "Namespace:    terraform-enterprise"
echo "TFE Hostname: tfe.example.com"
echo ""

# Initialize Terraform
echo "=== Initializing Terraform ==="
terraform init

# Plan first
echo ""
echo "=== Running Terraform Plan ==="
terraform plan \
    -var-file=test.tfvars \
    -var="tfe_license=$TFE_LICENSE" \
    -var="tfe_encryption_password=$ENCRYPTION_PASSWORD" \
    -var="tls_certificate=$TLS_CERT" \
    -var="tls_private_key=$TLS_KEY" \
    -var="ca_certificate=$CA_CERT" \
    -out=tfplan

echo ""
echo "=== Plan Complete ==="
echo ""
read -p "Apply this plan? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

# Apply
echo ""
echo "=== Applying Terraform ==="
terraform apply tfplan

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Next steps:"
echo "1. Get the LoadBalancer IP:"
echo "   kubectl get svc -n terraform-enterprise"
echo ""
echo "2. Update DNS to point tfe.example.com to the LB IP"
echo ""
echo "3. Check TFE health:"
echo "   curl -k https://<LB_IP>/_health_check"
echo ""
echo "4. Access TFE:"
echo "   https://tfe.example.com"
echo ""
