# apptest/deployer/Dockerfile
# HashiCorp Terraform Cloud Agent - Tester Deployer

FROM gcr.io/cloud-marketplace-tools/k8s/deployer_envsubst

# Copy test schema and manifests
COPY schema.yaml /data/schema.yaml
COPY manifest /data/manifest

# Set the schema file location
ENV SCHEMA_FILE=/data/schema.yaml
