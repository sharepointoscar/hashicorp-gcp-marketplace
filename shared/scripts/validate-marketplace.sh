#!/bin/bash
# shared/scripts/validate-marketplace.sh
# Parameterized GCP Marketplace validation script
# Usage: validate-marketplace.sh <product-name> [--keep-deployment] [--cleanup] [--gcr-clean] [--cluster=<name>] [--zone=<zone>]

set -e

# Parse arguments
PRODUCT=""
KEEP_DEPLOYMENT=false
CLEANUP_ONLY=false
GCR_CLEAN=false
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
        --gcr-clean)
            GCR_CLEAN=true
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
    echo "Usage: validate-marketplace.sh <product-name> [--keep-deployment] [--cleanup] [--gcr-clean] [--cluster=<name>] [--zone=<zone>]"
    echo "Available products: vault, consul, nomad, terraform-enterprise"
    echo ""
    echo "Options:"
    echo "  --keep-deployment  Keep the test deployment after validation"
    echo "  --cleanup          Clean up all test namespaces and orphaned PVs, then exit"
    echo "  --gcr-clean        Delete ALL existing GCR images for this product before building"
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

    # Get all test namespaces (both apptest and product-specific)
    ALL_TEST_NS=$(kubectl get ns -o name 2>/dev/null | grep -E "apptest-|vault-|consul-|nomad-|terraform-enterprise-|boundary-" | cut -d'/' -f2)

    if [ -n "$ALL_TEST_NS" ]; then
        # First pass: Delete Config Connector resources in each namespace
        echo "Deleting Config Connector resources..."
        for ns in $ALL_TEST_NS; do
            # Check if Config Connector resources exist
            if kubectl get sqlinstance -n "$ns" &>/dev/null 2>&1; then
                echo "  Deleting CC resources in $ns..."
                kubectl delete storagebucket,redisinstance,sqluser,sqldatabase,sqlinstance --all -n "$ns" --wait=false 2>/dev/null || true
                kubectl delete configconnectorcontext --all -n "$ns" --wait=false 2>/dev/null || true
            fi
        done
    fi

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

    # Force delete stuck namespaces by removing finalizers
    echo "Force deleting stuck namespaces..."
    for ns in $(kubectl get ns 2>/dev/null | grep -E "apptest-|vault-|consul-|nomad-|terraform-enterprise-|boundary-" | grep Terminating | awk '{print $1}'); do
        echo "  Force deleting stuck namespace: $ns"

        # Remove finalizers from ConfigConnectorContext and RoleBindings
        for resource in configconnectorcontext rolebinding; do
            for item in $(kubectl get $resource -n "$ns" -o name 2>/dev/null); do
                kubectl patch "$item" -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            done
        done

        # Remove namespace finalizers
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

# Registry cleanup function - deletes ALL images for a product including untagged layers
# Supports both GCR (legacy) and Artifact Registry
registry_clean_all_images() {
    local registry="$1"
    local app_id="$2"

    echo "=================================================="
    echo "Cleaning ALL registry images for $app_id..."
    echo "=================================================="

    # Detect registry type
    if [[ "$registry" == *"pkg.dev"* ]]; then
        echo "Registry type: Artifact Registry"

        # Artifact Registry format - images are direct children
        local repos=(
            "${registry}/${app_id}"
            "${registry}/ubbagent"
            "${registry}/deployer"
            "${registry}/tester"
        )

        for repo in "${repos[@]}"; do
            echo ""
            echo "Cleaning repository: $repo"

            # Get all versions (digests)
            local versions
            versions=$(gcloud artifacts docker images list "$repo" --format='get(version)' 2>/dev/null || true)

            if [ -z "$versions" ]; then
                echo "  No images found"
                continue
            fi

            # Delete each version
            for version in $versions; do
                echo "  Deleting $repo@$version"
                gcloud artifacts docker images delete "$repo@$version" --delete-tags --quiet 2>/dev/null || true
            done
        done
    else
        echo "Registry type: GCR (deprecated)"

        # GCR format - images are nested under app_id
        local repos=(
            "${registry}/${app_id}"
            "${registry}/${app_id}/ubbagent"
            "${registry}/${app_id}/deployer"
            "${registry}/${app_id}/tester"
        )

        for repo in "${repos[@]}"; do
            echo ""
            echo "Cleaning repository: $repo"

            # Get all digests (including untagged)
            local digests
            digests=$(gcloud container images list-tags "$repo" --format='get(digest)' 2>/dev/null || true)

            if [ -z "$digests" ]; then
                echo "  No images found"
                continue
            fi

            # Delete each digest
            for digest in $digests; do
                echo "  Deleting $repo@$digest"
                gcloud container images delete "$repo@$digest" --force-delete-tags --quiet 2>/dev/null || true
            done
        done

        # Also clean any scan test images that might exist (GCR only)
        local test_repos=(
            "${registry}/${app_id}-scan-test"
            "${registry}/ubbagent-scan-test"
        )

        for repo in "${test_repos[@]}"; do
            local digests
            digests=$(gcloud container images list-tags "$repo" --format='get(digest)' 2>/dev/null || true)

            if [ -n "$digests" ]; then
                echo ""
                echo "Cleaning test repository: $repo"
                for digest in $digests; do
                    echo "  Deleting $repo@$digest"
                    gcloud container images delete "$repo@$digest" --force-delete-tags --quiet 2>/dev/null || true
                done
            fi
        done
    fi

    echo ""
    echo "✓ Registry cleanup complete for $app_id"
    echo ""
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

# Auto-detect license file for Enterprise products
LICENSE_FILE=$(ls "$PRODUCT_DIR"/*.hclic 2>/dev/null | head -1)
LICENSE_CONTENT=""
LICENSE_PARAM_NAME=""

if [ -n "$LICENSE_FILE" ]; then
    LICENSE_CONTENT=$(cat "$LICENSE_FILE")
    # Set the parameter name based on product
    case "$PRODUCT" in
        consul)
            LICENSE_PARAM_NAME="consulLicense"
            ;;
        vault)
            LICENSE_PARAM_NAME="vaultLicense"
            ;;
        nomad)
            LICENSE_PARAM_NAME="nomadLicense"
            ;;
        boundary)
            LICENSE_PARAM_NAME="boundaryLicense"
            ;;
        terraform-enterprise)
            LICENSE_PARAM_NAME="tfeLicense"
            ;;
    esac
fi

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
echo "  GCR_CLEAN: $GCR_CLEAN"
echo "  GKE_CLUSTER: ${CLUSTER_NAME:-<current context>}"
echo "  GKE_ZONE: ${CLUSTER_ZONE:-<current context>}"
echo "  LICENSE_FILE: ${LICENSE_FILE:-<not found>}"
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

# Step 3: Clean registry images (if requested)
if [ "$GCR_CLEAN" = true ]; then
    print_step 3 "Cleaning All Registry Images"
    registry_clean_all_images "$REGISTRY" "$APP_ID"
    print_success "Registry cleanup complete"
else
    print_step 3 "Skipping Registry Cleanup (use --gcr-clean to enable)"
fi

# Step 4: Build and release images (clean, build, push, tag minor versions)
print_step 4 "Building and Releasing Container Images"
cd "$PRODUCT_DIR"
make REGISTRY="$REGISTRY" TAG="$TAG" release
print_success "All images built, pushed, and tagged with minor versions"

# Step 5: Verify schema
print_step 5 "Verifying Schema"
mpdev /scripts/doctor.py --deployer="$DEPLOYER_IMAGE" || true
print_success "Schema verification complete"

# Step 6: Test installation
print_step 6 "Testing Installation with mpdev install"

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

    # Build parameters JSON
    PARAMS='{"name": "'$PRODUCT'", "namespace": "'$TEST_NAMESPACE'", "replicas": 1, "reportingSecret": "fake-reporting-secret"'
    if [ -n "$LICENSE_PARAM_NAME" ] && [ -n "$LICENSE_CONTENT" ]; then
        # Escape special characters in license for JSON
        ESCAPED_LICENSE=$(echo "$LICENSE_CONTENT" | sed 's/"/\\"/g' | tr -d '\n')
        PARAMS="$PARAMS, \"$LICENSE_PARAM_NAME\": \"$ESCAPED_LICENSE\""
        echo "  Including license parameter: $LICENSE_PARAM_NAME"
    fi
    PARAMS="$PARAMS}"

    mpdev install \
        --deployer="$DEPLOYER_IMAGE" \
        --parameters="$PARAMS" || {
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

# Step 7: Run full verification
print_step 7 "Running Full Verification (mpdev verify)"

if [ "$KEEP_DEPLOYMENT" = true ]; then
    print_warning "Skipping mpdev verify (--keep-deployment flag set)"
elif kubectl cluster-info &> /dev/null; then
    echo "Running mpdev verify..."

    # Build verify parameters if license is available
    if [ -n "$LICENSE_PARAM_NAME" ] && [ -n "$LICENSE_CONTENT" ]; then
        ESCAPED_LICENSE=$(echo "$LICENSE_CONTENT" | sed 's/"/\\"/g' | tr -d '\n')
        VERIFY_PARAMS='{"'$LICENSE_PARAM_NAME'": "'$ESCAPED_LICENSE'"}'
        echo "  Including license parameter: $LICENSE_PARAM_NAME"
        mpdev verify --deployer="$DEPLOYER_IMAGE" --parameters="$VERIFY_PARAMS" || {
            print_error "mpdev verify failed"
            exit 1
        }
    else
        mpdev verify --deployer="$DEPLOYER_IMAGE" || {
            print_error "mpdev verify failed"
            exit 1
        }
    fi
    print_success "Full verification passed"
else
    print_warning "No Kubernetes cluster available. Skipping mpdev verify."
fi

# Step 8: Check vulnerability scans
print_step 8 "Checking Vulnerability Scans"
echo "Note: Vulnerability scanning requires Container Analysis API to be enabled."

# Function to scan an image and report vulnerabilities
scan_image() {
    local image_path="$1"
    local image_name="$2"

    echo ""
    echo "─────────────────────────────────────────────────"
    echo "Scanning: $image_name"
    echo "  Image: $image_path"

    # Get vulnerability summary - use --show-package-vulnerability for full data
    echo "  Fetching vulnerability data..."
    local vuln_output
    vuln_output=$(gcloud artifacts docker images describe "$image_path" --show-package-vulnerability --format=yaml 2>&1)

    if [ $? -ne 0 ]; then
        echo "  Status: Error fetching image data"
        echo "  Details: $vuln_output"
        return
    fi

    if echo "$vuln_output" | grep -q "package_vulnerability_summary"; then
        echo "  Status: Scan complete"
    else
        echo "  Status: Scan pending or no vulnerabilities found"
        return
    fi

    # Count vulnerabilities by severity (use head -1 to avoid multiline issues)
    local critical=$(echo "$vuln_output" | grep "effectiveSeverity: CRITICAL" | wc -l | tr -d ' ')
    local high=$(echo "$vuln_output" | grep "effectiveSeverity: HIGH" | wc -l | tr -d ' ')
    local medium=$(echo "$vuln_output" | grep "effectiveSeverity: MEDIUM" | wc -l | tr -d ' ')
    local low=$(echo "$vuln_output" | grep "effectiveSeverity: LOW" | wc -l | tr -d ' ')

    # Ensure we have integers
    critical=${critical:-0}
    high=${high:-0}
    medium=${medium:-0}
    low=${low:-0}

    echo ""
    echo "  ┌─────────────────────────────────────┐"
    echo "  │ Vulnerability Summary               │"
    echo "  ├─────────────────────────────────────┤"
    printf "  │ CRITICAL: %-3s                      │\n" "$critical"
    printf "  │ HIGH:     %-3s                      │\n" "$high"
    printf "  │ MEDIUM:   %-3s                      │\n" "$medium"
    printf "  │ LOW:      %-3s                      │\n" "$low"
    echo "  └─────────────────────────────────────┘"

    # Warn on critical or high vulnerabilities and show CVE IDs
    if [ "$critical" -gt 0 ] 2>/dev/null; then
        echo -e "  \033[0;31m⚠ CRITICAL vulnerabilities found - action required!\033[0m"
        echo "  CRITICAL CVEs:"
        echo "$vuln_output" | grep -o "CVE-[0-9]\{4\}-[0-9]*" | sort -u | while read cve; do
            echo "    - $cve"
        done | head -10
    fi
    if [ "$high" -gt 0 ] 2>/dev/null; then
        echo -e "  \033[1;33m⚠ HIGH vulnerabilities found - review recommended\033[0m"
        echo "  HIGH CVEs (showing up to 10):"
        # Extract CVEs from HIGH severity sections
        echo "$vuln_output" | awk '/effectiveSeverity: HIGH/{found=1} found && /noteName:.*CVE/{print; found=0}' | \
            grep -o "CVE-[0-9]\{4\}-[0-9]*" | sort -u | while read cve; do
            echo "    - $cve"
        done | head -10
    fi
}

# Determine registry type and image paths
if [[ "$REGISTRY" == *"pkg.dev"* ]]; then
    # Artifact Registry format
    echo "Registry type: Artifact Registry"
    scan_image "${REGISTRY}/${APP_ID}:${TAG}" "${APP_ID}"
    scan_image "${REGISTRY}/ubbagent:${TAG}" "ubbagent"
    scan_image "${REGISTRY}/deployer:${TAG}" "deployer"
    scan_image "${REGISTRY}/tester:${TAG}" "tester"
else
    # GCR format (legacy)
    echo "Registry type: GCR (deprecated)"
    scan_image "${REGISTRY}/${APP_ID}:${TAG}" "${APP_ID}"
    scan_image "${REGISTRY}/${APP_ID}/ubbagent:${TAG}" "ubbagent"
    scan_image "${REGISTRY}/${APP_ID}/deployer:${TAG}" "deployer"
    scan_image "${REGISTRY}/${APP_ID}/tester:${TAG}" "tester"
fi

print_success "Vulnerability scan check complete"

# Summary
echo ""
echo "=================================================="
print_success "Validation Complete for $PRODUCT_DISPLAY!"
echo "=================================================="
echo ""
echo "Images validated:"
if [[ "$REGISTRY" == *"pkg.dev"* ]]; then
    echo "  - ${REGISTRY}/${APP_ID}:${TAG}"
    echo "  - ${REGISTRY}/ubbagent:${TAG}"
    echo "  - ${REGISTRY}/deployer:${TAG}"
    echo "  - ${REGISTRY}/tester:${TAG}"
else
    echo "  - ${REGISTRY}/${APP_ID}:${TAG}"
    echo "  - ${REGISTRY}/${APP_ID}/ubbagent:${TAG}"
    echo "  - ${REGISTRY}/${APP_ID}/deployer:${TAG}"
    echo "  - ${REGISTRY}/${APP_ID}/tester:${TAG}"
fi
echo ""
