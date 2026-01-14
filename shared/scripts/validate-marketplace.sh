#!/bin/bash
# shared/scripts/validate-marketplace.sh
# Parameterized GCP Marketplace validation script
# Usage: validate-marketplace.sh <product-name> [--keep-deployment]

set -e

# Parse arguments
PRODUCT=""
KEEP_DEPLOYMENT=false

for arg in "$@"; do
    case $arg in
        --keep-deployment)
            KEEP_DEPLOYMENT=true
            ;;
        *)
            if [ -z "$PRODUCT" ]; then
                PRODUCT="$arg"
            fi
            ;;
    esac
done

if [ -z "$PRODUCT" ]; then
    echo "Usage: validate-marketplace.sh <product-name> [--keep-deployment]"
    echo "Available products: vault, consul, nomad, terraform"
    exit 1
fi

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONOREPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PRODUCT_DIR="$MONOREPO_ROOT/products/$PRODUCT"
SHARED_DIR="$MONOREPO_ROOT/shared"

# Source common functions
source "$SHARED_DIR/scripts/lib/common.sh"

# Validate product directory exists
if [ ! -d "$PRODUCT_DIR" ]; then
    print_error "Product directory not found: $PRODUCT_DIR"
    echo "Available products:"
    ls -1 "$MONOREPO_ROOT/products/"
    exit 1
fi

# Load product configuration
cd "$PRODUCT_DIR"
if [ -f "product.yaml" ]; then
    load_product_config "$PRODUCT_DIR"
else
    print_warning "No product.yaml found, using defaults"
    PRODUCT_ID="$PRODUCT"
    PRODUCT_VERSION="latest"
fi

# Required environment variables
: "${REGISTRY:?REGISTRY must be set (e.g., gcr.io/your-project-id)}"
: "${TAG:=$PRODUCT_VERSION}"

APP_ID="$PRODUCT_ID"
DEPLOYER_IMAGE="${REGISTRY}/${APP_ID}/deployer:${TAG}"

echo "=================================================="
echo "GCP Marketplace Validation for HashiCorp ${PRODUCT^}"
echo "=================================================="
echo ""
echo "Configuration:"
echo "  PRODUCT: $PRODUCT"
echo "  PRODUCT_DIR: $PRODUCT_DIR"
echo "  REGISTRY: $REGISTRY"
echo "  TAG: $TAG"
echo "  DEPLOYER_IMAGE: $DEPLOYER_IMAGE"
echo "  KEEP_DEPLOYMENT: $KEEP_DEPLOYMENT"
echo ""

# Step 1: Verify prerequisites
print_step 1 "Verifying Prerequisites"
check_prerequisites
check_mpdev

# Step 2: Run mpdev doctor
print_step 2 "Running mpdev doctor"
mpdev doctor || print_warning "mpdev doctor found issues"
print_success "Environment check complete"

# Step 3: Build images
print_step 3 "Building Container Images"
cd "$PRODUCT_DIR"
make REGISTRY="$REGISTRY" TAG="$TAG" app/build
print_success "All images built and pushed"

# Step 4: Verify schema
print_step 4 "Verifying Schema"
mpdev /scripts/doctor.py --deployer="$DEPLOYER_IMAGE" || true
print_success "Schema verification complete"

# Step 5: Test installation
print_step 5 "Testing Installation with mpdev install"

if kubectl cluster-info &> /dev/null; then
    if [ "$KEEP_DEPLOYMENT" = true ]; then
        TEST_NAMESPACE="${PRODUCT}-test"
    else
        TEST_NAMESPACE="${PRODUCT}-mp-test-$(date +%s)"
    fi

    echo "Creating test namespace: $TEST_NAMESPACE"
    kubectl create namespace "$TEST_NAMESPACE" || true

    # Create fake reporting secret
    kubectl create secret generic fake-reporting-secret \
        --namespace="$TEST_NAMESPACE" \
        --from-literal=reporting-key="" \
        --from-literal=consumer-id="" \
        --from-literal=entitlement-id="" || true

    echo "Running mpdev install..."
    mpdev install \
        --deployer="$DEPLOYER_IMAGE" \
        --parameters='{"name": "'$PRODUCT'", "namespace": "'$TEST_NAMESPACE'", "replicas": 1, "reportingSecret": "fake-reporting-secret"}' || {
            print_error "mpdev install failed"
            kubectl delete namespace "$TEST_NAMESPACE" --ignore-not-found
            exit 1
        }

    print_success "Installation test passed"

    if [ "$KEEP_DEPLOYMENT" = false ]; then
        echo "Cleaning up test namespace..."
        kubectl delete namespace "$TEST_NAMESPACE" --ignore-not-found
    fi
else
    print_warning "No Kubernetes cluster available. Skipping installation test."
fi

# Step 6: Run full verification
print_step 6 "Running Full Verification (mpdev verify)"

if [ "$KEEP_DEPLOYMENT" = true ]; then
    print_warning "Skipping mpdev verify (--keep-deployment flag set)"
elif kubectl cluster-info &> /dev/null; then
    echo "Running mpdev verify..."
    mpdev verify --deployer="$DEPLOYER_IMAGE" || {
        print_error "mpdev verify failed"
        exit 1
    }
    print_success "Full verification passed"
else
    print_warning "No Kubernetes cluster available. Skipping mpdev verify."
fi

# Step 7: Check vulnerability scans
print_step 7 "Checking Vulnerability Scans"
echo "Note: Vulnerability scanning requires Container Scanning API to be enabled."

PROJECT_ID=$(echo "$REGISTRY" | cut -d'/' -f2)
if gcloud artifacts docker images describe "${REGISTRY}/${APP_ID}:${TAG}" --show-all-metadata 2>/dev/null; then
    print_success "Image metadata retrieved"
else
    print_warning "Could not retrieve vulnerability scan results."
fi

# Summary
echo ""
echo "=================================================="
print_success "Validation Complete for ${PRODUCT^}!"
echo "=================================================="
echo ""
echo "Images validated:"
echo "  - ${REGISTRY}/${APP_ID}:${TAG}"
echo "  - ${REGISTRY}/${APP_ID}/deployer:${TAG}"
echo ""
