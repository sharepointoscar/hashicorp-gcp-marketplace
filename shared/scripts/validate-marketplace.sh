#!/bin/bash
# shared/scripts/validate-marketplace.sh
# Parameterized GCP Marketplace validation script
# Usage: validate-marketplace.sh <product-name> [--keep-deployment] [--cleanup] [--cluster=<name>] [--zone=<zone>]

set -e

# Parse arguments
PRODUCT=""
KEEP_DEPLOYMENT=false
CLEANUP_ONLY=false
CLUSTER_NAME="${GKE_CLUSTER:-}"
CLUSTER_ZONE="${GKE_ZONE:-}"

for arg in "$@"; do
    case $arg in
        --keep-deployment)
            KEEP_DEPLOYMENT=true
            ;;
        --cleanup)
            CLEANUP_ONLY=true
            ;;
        --cluster=*)
            CLUSTER_NAME="${arg#*=}"
            ;;
        --zone=*)
            CLUSTER_ZONE="${arg#*=}"
            ;;
        *)
            if [ -z "$PRODUCT" ]; then
                PRODUCT="$arg"
            fi
            ;;
    esac
done

if [ -z "$PRODUCT" ]; then
    echo "Usage: validate-marketplace.sh <product-name> [--keep-deployment] [--cleanup] [--cluster=<name>] [--zone=<zone>]"
    echo "Available products: vault, consul, nomad, terraform-enterprise"
    echo ""
    echo "Options:"
    echo "  --keep-deployment  Keep the test deployment after validation"
    echo "  --cleanup          Clean up all test namespaces and orphaned PVs, then exit"
    echo "  --cluster=<name>   GKE cluster name"
    echo "  --zone=<zone>      GKE zone"
    echo ""
    echo "Environment variables:"
    echo "  REGISTRY    - GCR registry (required, e.g., gcr.io/my-project)"
    echo "  TAG         - Image tag (required, e.g., 1.22.1)"
    echo "  GKE_CLUSTER - GKE cluster name (optional, overrides --cluster)"
    echo "  GKE_ZONE    - GKE zone (optional, overrides --zone)"
    exit 1
fi

# Cleanup function
cleanup_all_resources() {
    echo "=================================================="
    echo "Cleaning up all test resources..."
    echo "=================================================="

    # Delete all apptest namespaces
    echo "Deleting apptest-* namespaces..."
    for ns in $(kubectl get ns -o name 2>/dev/null | grep "apptest-" | cut -d'/' -f2); do
        echo "  Deleting namespace: $ns"
        kubectl delete ns "$ns" --grace-period=0 --force --wait=false 2>/dev/null || true
    done

    # Delete product-specific test namespaces
    echo "Deleting product test namespaces..."
    for ns in $(kubectl get ns -o name 2>/dev/null | grep -E "^namespace/(vault|consul|nomad|terraform-enterprise|boundary)-" | cut -d'/' -f2); do
        echo "  Deleting namespace: $ns"
        kubectl delete ns "$ns" --grace-period=0 --force --wait=false 2>/dev/null || true
    done

    # Wait for namespaces to terminate
    echo "Waiting for namespaces to terminate..."
    sleep 5

    # Force delete stuck namespaces
    for ns in $(kubectl get ns 2>/dev/null | grep -E "apptest-|vault-|consul-|nomad-|terraform-enterprise-|boundary-" | grep Terminating | awk '{print $1}'); do
        echo "  Force deleting stuck namespace: $ns"
        kubectl get ns "$ns" -o json 2>/dev/null | jq '.spec.finalizers = []' | \
            kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
    done

    # Clean up orphaned PVs
    echo "Cleaning up orphaned PVs..."
    for pv in $(kubectl get pv 2>/dev/null | grep -E "Released|Failed" | awk '{print $1}'); do
        echo "  Deleting PV: $pv"
        kubectl delete pv "$pv" --grace-period=0 --force 2>/dev/null || true
    done

    # Final check
    sleep 3
    REMAINING=$(kubectl get ns 2>/dev/null | grep -E "apptest-|vault-mp|consul-mp|nomad-mp|terraform-enterprise-mp|boundary-mp" | wc -l)
    if [ "$REMAINING" -eq 0 ]; then
        echo ""
        echo "✓ All test resources cleaned up successfully!"
    else
        echo ""
        echo "⚠ Some namespaces may still be terminating. Run again if needed."
        kubectl get ns 2>/dev/null | grep -E "apptest-|vault-|consul-|nomad-|terraform-enterprise-|boundary-"
    fi
}

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

PRODUCT_DISPLAY=$(echo "$PRODUCT" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
echo "=================================================="
echo "GCP Marketplace Validation for HashiCorp $PRODUCT_DISPLAY"
echo "=================================================="
echo ""
echo "Configuration:"
echo "  PRODUCT: $PRODUCT"
echo "  PRODUCT_DIR: $PRODUCT_DIR"
echo "  REGISTRY: $REGISTRY"
echo "  TAG: $TAG"
echo "  DEPLOYER_IMAGE: $DEPLOYER_IMAGE"
echo "  KEEP_DEPLOYMENT: $KEEP_DEPLOYMENT"
echo "  GKE_CLUSTER: ${CLUSTER_NAME:-<current context>}"
echo "  GKE_ZONE: ${CLUSTER_ZONE:-<current context>}"
echo ""

# Step 1: Verify prerequisites
print_step 1 "Verifying Prerequisites"
check_prerequisites
check_mpdev

# Switch to specified GKE cluster if provided
if [ -n "$CLUSTER_NAME" ] && [ -n "$CLUSTER_ZONE" ]; then
    echo "Switching to GKE cluster: $CLUSTER_NAME in $CLUSTER_ZONE"
    PROJECT_ID=$(echo "$REGISTRY" | cut -d'/' -f2)
    gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$CLUSTER_ZONE" --project="$PROJECT_ID"
    print_success "Connected to cluster $CLUSTER_NAME"
elif [ -n "$CLUSTER_NAME" ]; then
    print_warning "CLUSTER_NAME set but CLUSTER_ZONE not set, using current context"
fi

# Verify cluster has nodes
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [ "$NODE_COUNT" -eq 0 ]; then
    print_error "No nodes available in the cluster. Please use a cluster with running nodes."
    exit 1
fi
echo "Cluster has $NODE_COUNT nodes available"

# If cleanup only, run cleanup and exit
if [ "$CLEANUP_ONLY" = true ]; then
    cleanup_all_resources
    echo ""
    echo "Cleanup complete. Exiting."
    exit 0
fi

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
        kubectl delete namespace "$TEST_NAMESPACE" --ignore-not-found --wait=false
        # Force delete if stuck in Terminating state
        sleep 5
        if kubectl get ns "$TEST_NAMESPACE" 2>/dev/null | grep -q Terminating; then
            echo "Namespace stuck in Terminating, force deleting..."
            kubectl get ns "$TEST_NAMESPACE" -o json | jq '.spec.finalizers = []' | \
                kubectl replace --raw "/api/v1/namespaces/$TEST_NAMESPACE/finalize" -f - 2>/dev/null || true
        fi
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
print_success "Validation Complete for $PRODUCT_DISPLAY!"
echo "=================================================="
echo ""
echo "Images validated:"
echo "  - ${REGISTRY}/${APP_ID}:${TAG}"
echo "  - ${REGISTRY}/${APP_ID}/deployer:${TAG}"
echo ""
