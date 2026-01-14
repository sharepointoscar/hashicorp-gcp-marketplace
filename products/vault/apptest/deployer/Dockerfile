# apptest/deployer/Dockerfile

# Build the tester deployer for mpdev verify
FROM gcr.io/cloud-marketplace-tools/k8s/deployer_envsubst

# Copy tester manifest
COPY manifest /data/manifest

# Copy test schema
COPY schema.yaml /data/schema.yaml
