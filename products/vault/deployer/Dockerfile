# deployer/Dockerfile

# Use the envsubst base deployer from marketplace-tools
FROM gcr.io/cloud-marketplace-tools/k8s/deployer_envsubst

# Copy manifest templates
COPY manifest /data/manifest

# Copy schema (required at /data/schema.yaml)
COPY schema.yaml /data/schema.yaml

# Copy test schema and tester manifest for mpdev verify smoke tests
COPY apptest/deployer/schema.yaml /data-test/schema.yaml
COPY apptest/deployer/manifest /data-test/manifest
