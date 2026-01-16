#!/bin/bash
# scripts/release.sh
# Build, clean, and release all TFE GCP Marketplace artifacts
# Usage: ./scripts/release.sh [--clean] [--build] [--info]
#   --clean  : Delete all artifacts from AR and GCS
#   --build  : Build and push all artifacts (default if no flags)
#   --info   : Display Partner Portal configuration info
#   --all    : Clean, build, and display info

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Source Makefile variables
VERSION=$(grep "^VERSION :=" Makefile | cut -d'=' -f2 | tr -d ' ')
MINOR_VERSION=$(echo "$VERSION" | cut -d. -f1,2)
AR_REGISTRY="us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace"
TF_MODULE_BUCKET="gs://ibm-software-mp-project-test-tf-modules"
APP_ID="terraform-enterprise"

#=============================================================================
# FUNCTIONS
#=============================================================================

clean_artifacts() {
    echo "=== CLEANING ALL ARTIFACTS ==="
    echo ""

    # Clean Artifact Registry
    echo "Cleaning Artifact Registry..."
    IMAGES=$(gcloud artifacts docker images list "$AR_REGISTRY" --include-tags --format="value(package,version)" 2>/dev/null || true)
    if [ -n "$IMAGES" ]; then
        echo "$IMAGES" | while read -r pkg digest; do
            if [ -n "$pkg" ] && [ -n "$digest" ]; then
                echo "  Deleting: $pkg@$digest"
                gcloud artifacts docker images delete "$pkg@$digest" --quiet --delete-tags 2>/dev/null || true
            fi
        done
    else
        echo "  (already empty)"
    fi

    # Clean GCS bucket
    echo ""
    echo "Cleaning GCS bucket..."
    if gsutil ls "$TF_MODULE_BUCKET/$APP_ID/" &>/dev/null; then
        gsutil -m rm -r "$TF_MODULE_BUCKET/$APP_ID/**" 2>/dev/null || true
        echo "  Deleted all files from $TF_MODULE_BUCKET/$APP_ID/"
    else
        echo "  (already empty)"
    fi

    # Clean local build artifacts
    echo ""
    echo "Cleaning local build artifacts..."
    rm -rf .build/
    mkdir -p .build
    echo "  Cleaned .build/"

    echo ""
    echo "=== CLEANUP COMPLETE ==="
}

verify_clean() {
    echo ""
    echo "=== VERIFYING CLEAN STATE ==="
    echo ""
    echo "Artifact Registry:"
    COUNT=$(gcloud artifacts docker images list "$AR_REGISTRY" --format="value(package)" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$COUNT" -eq "0" ]; then
        echo "  ✓ Empty (0 images)"
    else
        echo "  ✗ $COUNT images still present"
        gcloud artifacts docker images list "$AR_REGISTRY" --include-tags --format="table(package,tags)"
    fi

    echo ""
    echo "GCS Bucket:"
    if gsutil ls "$TF_MODULE_BUCKET/$APP_ID/" &>/dev/null; then
        echo "  ✗ Files still present:"
        gsutil ls -r "$TF_MODULE_BUCKET/$APP_ID/"
    else
        echo "  ✓ Empty"
    fi
}

build_artifacts() {
    echo "=== BUILDING ALL ARTIFACTS ==="
    echo ""

    # Build TFE image
    echo "Building TFE image..."
    make .build/tfe

    # Build UBB agent image
    echo ""
    echo "Building UBB agent image..."
    make .build/ubbagent

    # Build and push Helm chart
    echo ""
    echo "Building and pushing Helm chart..."
    make helm/push

    # Add minor version tags
    echo ""
    echo "Adding minor version tags..."
    make tags/minor

    # Upload Terraform module
    echo ""
    echo "Uploading Terraform module..."
    make terraform/upload

    echo ""
    echo "=== BUILD COMPLETE ==="
}

display_info() {
    echo ""
    echo "============================================================================="
    echo "                    GCP PARTNER PORTAL CONFIGURATION"
    echo "============================================================================="
    echo ""

    # Get chart digest
    CHART_DIGEST=$(gcloud artifacts docker images describe \
        "$AR_REGISTRY/terraform-enterprise-chart:$VERSION" \
        --format="value(image_summary.digest)" 2>/dev/null || echo "N/A")

    # Get TFE image digest
    TFE_DIGEST=$(gcloud artifacts docker images describe \
        "$AR_REGISTRY/tfe:$VERSION" \
        --format="value(image_summary.digest)" 2>/dev/null || echo "N/A")

    # Get UBB agent digest
    UBB_DIGEST=$(gcloud artifacts docker images describe \
        "$AR_REGISTRY/ubbagent:$VERSION" \
        --format="value(image_summary.digest)" 2>/dev/null || echo "N/A")

    echo "DEPLOYMENT CONFIGURATION TAB"
    echo "----------------------------"
    echo "Helm Chart URL:           $AR_REGISTRY/terraform-enterprise-chart"
    echo "Helm Chart Digest:        $CHART_DIGEST"
    echo "Display Tag:              $MINOR_VERSION"
    echo "Full Version:             $VERSION"
    echo "Terraform Module:         $TF_MODULE_BUCKET/$APP_ID/$VERSION/$APP_ID-$VERSION.zip"
    echo ""
    echo "ARTIFACTS IN REGISTRY"
    echo "---------------------"
    printf "%-20s %-15s %s\n" "IMAGE" "TAGS" "DIGEST"
    printf "%-20s %-15s %s\n" "Helm Chart" "$MINOR_VERSION, $VERSION" "$CHART_DIGEST"
    printf "%-20s %-15s %s\n" "TFE" "$MINOR_VERSION, $VERSION" "$TFE_DIGEST"
    printf "%-20s %-15s %s\n" "UBB Agent" "$MINOR_VERSION, $VERSION" "$UBB_DIGEST"
    echo ""
    echo "TFE UPSTREAM VERSION"
    echo "--------------------"
    TFE_UPSTREAM=$(grep "^TFE_UPSTREAM_VERSION" Makefile | cut -d'=' -f2 | tr -d ' ?')
    echo "$TFE_UPSTREAM"
    echo ""
    echo "REQUIRED IAM ROLES"
    echo "------------------"
    echo "roles/container.developer"
    echo "roles/cloudsql.admin"
    echo "roles/redis.admin"
    echo "roles/storage.admin"
    echo "roles/iam.serviceAccountAdmin"
    echo "roles/iam.serviceAccountUser"
    echo "roles/iam.workloadIdentityUser"
    echo "roles/servicenetworking.networksAdmin"
    echo "roles/compute.networkAdmin"
    echo "roles/serviceusage.serviceUsageAdmin"
    echo ""
    echo "============================================================================="
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --clean    Delete all artifacts from AR and GCS"
    echo "  --build    Build and push all artifacts"
    echo "  --info     Display Partner Portal configuration info"
    echo "  --all      Clean, build, and display info"
    echo "  --help     Show this help message"
    echo ""
    echo "If no options provided, defaults to --build --info"
}

#=============================================================================
# MAIN
#=============================================================================

DO_CLEAN=false
DO_BUILD=false
DO_INFO=false

# Parse arguments
if [ $# -eq 0 ]; then
    DO_BUILD=true
    DO_INFO=true
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            DO_CLEAN=true
            shift
            ;;
        --build)
            DO_BUILD=true
            shift
            ;;
        --info)
            DO_INFO=true
            shift
            ;;
        --all)
            DO_CLEAN=true
            DO_BUILD=true
            DO_INFO=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

echo "=== TFE GCP Marketplace Release Script ==="
echo "Version: $VERSION"
echo "Minor Version: $MINOR_VERSION"
echo ""

if $DO_CLEAN; then
    clean_artifacts
    verify_clean
fi

if $DO_BUILD; then
    build_artifacts
fi

if $DO_INFO; then
    display_info
fi

echo ""
echo "Done."
