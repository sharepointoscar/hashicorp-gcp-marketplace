# Dockerfile - TFE Deployer for GCP Marketplace
# Uses deployer_helm to deploy TFE Helm chart

ARG MARKETPLACE_TOOLS_TAG
ARG REGISTRY
ARG TAG

# -----------------------------------------------------------------------------
# Build Stage: Package Helm chart and process schemas
# -----------------------------------------------------------------------------
FROM marketplace.gcr.io/google/c2d-debian11 AS build

ARG REGISTRY
ARG TAG

# Install envsubst
RUN apt-get update && apt-get install -y gettext-base && rm -rf /var/lib/apt/lists/*

# Copy chart and schemas
# Copy chart directory - the chart files should be directly under /tmp/chart/
COPY chart/terraform-enterprise /tmp/chart
COPY apptest/deployer/schema.yaml /tmp/apptest-schema.yaml
COPY schema.yaml /tmp/schema.yaml

# Package Helm chart for deployer
# deployer_helm expects: tarball extracts to chart/ with Chart.yaml inside
RUN cd /tmp && tar -czvf terraform-enterprise.tar.gz chart

# Package Helm chart for tester
RUN mkdir -p /tmp/test && \
    cp -r /tmp/chart /tmp/test/ && \
    cd /tmp/test && \
    tar -czvf terraform-enterprise.tar.gz chart

# Process schema.yaml with REGISTRY and TAG substitution
RUN cat /tmp/schema.yaml \
    | env -i "REGISTRY=${REGISTRY}" "TAG=${TAG}" envsubst \
    > /tmp/schema.yaml.processed \
    && mv /tmp/schema.yaml.processed /tmp/schema.yaml

# Process apptest schema.yaml
RUN cat /tmp/apptest-schema.yaml \
    | env -i "REGISTRY=${REGISTRY}" "TAG=${TAG}" envsubst \
    > /tmp/apptest-schema.yaml.processed \
    && mv /tmp/apptest-schema.yaml.processed /tmp/apptest-schema.yaml

# -----------------------------------------------------------------------------
# Final Stage: Deployer image
# -----------------------------------------------------------------------------
FROM gcr.io/cloud-marketplace-tools/k8s/deployer_helm:${MARKETPLACE_TOOLS_TAG}

# Copy packaged chart to data directory
COPY --from=build /tmp/terraform-enterprise.tar.gz /data/chart/

# Copy test chart to data-test directory
COPY --from=build /tmp/test/terraform-enterprise.tar.gz /data-test/chart/

# Copy processed schemas
COPY --from=build /tmp/apptest-schema.yaml /data-test/schema.yaml
COPY --from=build /tmp/schema.yaml /data/

# TFE requires extended timeouts (>600s to start)
ENV WAIT_FOR_READY_TIMEOUT=1800
ENV TESTER_TIMEOUT=1800
