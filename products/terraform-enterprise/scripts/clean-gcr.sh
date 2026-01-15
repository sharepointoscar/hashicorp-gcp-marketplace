#!/bin/bash
# scripts/clean-gcr.sh
# Delete all images from GCR before rebuilding

set -e

# Required: REGISTRY environment variable
if [ -z "$REGISTRY" ]; then
    echo "ERROR: REGISTRY environment variable is required"
    echo "Example: REGISTRY=gcr.io/your-project-id ./scripts/clean-gcr.sh"
    exit 1
fi

APP_ID="terraform-enterprise"

echo "=== Cleaning GCR images for $APP_ID ==="
echo "Registry: $REGISTRY"
echo ""

# Images to clean (all images from click-to-deploy model)
IMAGES=(
    "$REGISTRY/$APP_ID"
    "$REGISTRY/$APP_ID/deployer"
    "$REGISTRY/$APP_ID/ubbagent"
    "$REGISTRY/$APP_ID/tester"
    "$REGISTRY/$APP_ID/postgresql"
    "$REGISTRY/$APP_ID/redis"
    "$REGISTRY/$APP_ID/minio"
)

for img in "${IMAGES[@]}"; do
    echo "--- Cleaning $img ---"

    # Get all digests (tagged and untagged)
    digests=$(gcloud container images list-tags "$img" --format="get(digest)" 2>/dev/null || true)

    if [ -z "$digests" ]; then
        echo "No images found"
        continue
    fi

    # Delete each digest
    for digest in $digests; do
        echo "Deleting $img@$digest"
        gcloud container images delete "$img@$digest" --quiet --force-delete-tags 2>/dev/null || true
    done
done

echo ""
echo "=== Cleanup complete ==="
