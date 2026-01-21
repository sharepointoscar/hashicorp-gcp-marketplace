# products/terraform-enterprise/Makefile
# HashiCorp Terraform Enterprise - GCP Marketplace (Kubernetes App / mpdev Model)

APP_ID := terraform-enterprise
CHART_NAME := terraform-enterprise

# TFE upstream version (update to latest for CVE fixes)
TFE_UPSTREAM_VERSION ?= 1.1.3

# Version from schema.yaml publishedVersion (must match)
VERSION ?= 1.1.3
# Extract major version (e.g., 1 from 1.1.3) - required by GCP Marketplace
MAJOR_VERSION := $(shell echo $(VERSION) | cut -d. -f1)
# Extract minor version (e.g., 1.1 from 1.1.3) - required by GCP Marketplace
MINOR_VERSION := $(shell echo $(VERSION) | cut -d. -f1,2)

# Registry configuration (set via environment: REGISTRY=gcr.io/$PROJECT_ID)
REGISTRY ?= gcr.io/ibm-software-mp-project-test
TAG ?= $(VERSION)

# Marketplace tools tag (latest stable - upgraded for CVE fixes)
MARKETPLACE_TOOLS_TAG ?= 0.12.10

# Marketplace service name for image annotations
MP_SERVICE_NAME := services/terraform-enterprise.endpoints.ibm-software-mp-project-test.cloud.goog

# Build directory
BUILD_DIR := .build

# Include shared build infrastructure
include ../../shared/Makefile.common

# Extended timeouts for TFE (>600s startup)
VERIFY_WAIT_TIMEOUT := 1800
TESTER_TIMEOUT := 1800

#=============================================================================
# MAIN BUILD TARGET
#=============================================================================

.PHONY: app/build
app/build:: $(BUILD_DIR)/$(APP_ID)/tfe \
            $(BUILD_DIR)/$(APP_ID)/ubbagent \
            $(BUILD_DIR)/$(APP_ID)/deployer \
            $(BUILD_DIR)/$(APP_ID)/tester

#=============================================================================
# IMAGE TARGETS
#=============================================================================

# Ensure build directory exists
$(BUILD_DIR)/$(APP_ID):
	@mkdir -p $@

# TFE main image
$(BUILD_DIR)/$(APP_ID)/tfe: images/tfe/Dockerfile | $(BUILD_DIR)/$(APP_ID)
	$(call print_notice,Building TFE image...)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		--build-arg TFE_VERSION="$(TFE_UPSTREAM_VERSION)" \
		--annotation "com.googleapis.cloudmarketplace.product.service.name=$(MP_SERVICE_NAME)" \
		--tag "$(REGISTRY)/$(APP_ID):$(TAG)" \
		-f $< \
		--push images/tfe
	@touch $@
	$(call print_success,TFE image: $(REGISTRY)/$(APP_ID):$(TAG))

# UBB agent sidecar
$(BUILD_DIR)/$(APP_ID)/ubbagent: images/ubbagent/Dockerfile | $(BUILD_DIR)/$(APP_ID)
	$(call print_notice,Building UBB agent image...)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		--annotation "com.googleapis.cloudmarketplace.product.service.name=$(MP_SERVICE_NAME)" \
		--tag "$(REGISTRY)/$(APP_ID)/ubbagent:$(TAG)" \
		-f $< \
		--push images/ubbagent
	@touch $@
	$(call print_success,UBB agent image: $(REGISTRY)/$(APP_ID)/ubbagent:$(TAG))

# Deployer image (uses deployer_helm base)
$(BUILD_DIR)/$(APP_ID)/deployer: deployer/Dockerfile chart/terraform-enterprise/** schema.yaml apptest/deployer/schema.yaml | $(BUILD_DIR)/$(APP_ID)
	$(call print_notice,Building deployer image...)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		--build-arg REGISTRY="$(REGISTRY)/$(APP_ID)" \
		--build-arg TAG="$(TAG)" \
		--build-arg MARKETPLACE_TOOLS_TAG="$(MARKETPLACE_TOOLS_TAG)" \
		--annotation "com.googleapis.cloudmarketplace.product.service.name=$(MP_SERVICE_NAME)" \
		--tag "$(REGISTRY)/$(APP_ID)/deployer:$(TAG)" \
		-f $< \
		--push .
	@touch $@
	$(call print_success,Deployer image: $(REGISTRY)/$(APP_ID)/deployer:$(TAG))

# Tester image (for mpdev verify)
$(BUILD_DIR)/$(APP_ID)/tester: apptest/tester/Dockerfile apptest/tester/tester.sh apptest/tester/tests/** | $(BUILD_DIR)/$(APP_ID)
	$(call print_notice,Building tester image...)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		--annotation "com.googleapis.cloudmarketplace.product.service.name=$(MP_SERVICE_NAME)" \
		--tag "$(REGISTRY)/$(APP_ID)/tester:$(TAG)" \
		-f $< \
		--push apptest/tester
	@touch $@
	$(call print_success,Tester image: $(REGISTRY)/$(APP_ID)/tester:$(TAG))

#=============================================================================
# MPDEV TARGETS
#=============================================================================

.PHONY: app/verify
app/verify:
	$(call print_notice,Running mpdev verify...)
	mpdev verify \
		--deployer="$(REGISTRY)/$(APP_ID)/deployer:$(TAG)" \
		--wait_timeout=$(VERIFY_WAIT_TIMEOUT)

.PHONY: app/install
app/install:
	$(call print_notice,Running mpdev install...)
	mpdev install \
		--deployer="$(REGISTRY)/$(APP_ID)/deployer:$(TAG)" \
		--parameters='{ \
			"name": "tfe-test", \
			"namespace": "apptest-tfe-$(shell date +%s)" \
		}'

#=============================================================================
# HELM CHART TARGETS
#=============================================================================

.PHONY: helm/lint
helm/lint:
	$(call print_notice,Linting Helm chart...)
	helm lint chart/$(CHART_NAME)/

.PHONY: helm/template
helm/template:
	$(call print_notice,Rendering Helm chart templates...)
	helm template tfe chart/$(CHART_NAME)/ \
		--set tfeImage=$(REGISTRY)/$(APP_ID):$(TAG) \
		--set ubbagentImage=$(REGISTRY)/$(APP_ID)/ubbagent:$(TAG)

#=============================================================================
# SEMANTIC VERSION TAGGING (Required by GCP Marketplace)
# Tags: MAJOR (1), MINOR (1.1), PATCH (1.1.3)
#=============================================================================

.PHONY: gcr/tag-versions
gcr/tag-versions: gcr/tag-major gcr/tag-minor
	$(call print_success,All version tags added: $(MAJOR_VERSION) $(MINOR_VERSION) $(TAG))

.PHONY: gcr/tag-major
gcr/tag-major:
	$(call print_notice,Adding major version tags ($(MAJOR_VERSION))...)
	gcloud container images add-tag --quiet \
		$(REGISTRY)/$(APP_ID):$(TAG) \
		$(REGISTRY)/$(APP_ID):$(MAJOR_VERSION) 2>/dev/null || true
	gcloud container images add-tag --quiet \
		$(REGISTRY)/$(APP_ID)/ubbagent:$(TAG) \
		$(REGISTRY)/$(APP_ID)/ubbagent:$(MAJOR_VERSION) 2>/dev/null || true
	gcloud container images add-tag --quiet \
		$(REGISTRY)/$(APP_ID)/deployer:$(TAG) \
		$(REGISTRY)/$(APP_ID)/deployer:$(MAJOR_VERSION) 2>/dev/null || true
	gcloud container images add-tag --quiet \
		$(REGISTRY)/$(APP_ID)/tester:$(TAG) \
		$(REGISTRY)/$(APP_ID)/tester:$(MAJOR_VERSION) 2>/dev/null || true
	$(call print_success,Major version tags added: $(MAJOR_VERSION))

.PHONY: gcr/tag-minor
gcr/tag-minor:
	$(call print_notice,Adding minor version tags ($(MINOR_VERSION))...)
	gcloud container images add-tag --quiet \
		$(REGISTRY)/$(APP_ID):$(TAG) \
		$(REGISTRY)/$(APP_ID):$(MINOR_VERSION) 2>/dev/null || true
	gcloud container images add-tag --quiet \
		$(REGISTRY)/$(APP_ID)/ubbagent:$(TAG) \
		$(REGISTRY)/$(APP_ID)/ubbagent:$(MINOR_VERSION) 2>/dev/null || true
	gcloud container images add-tag --quiet \
		$(REGISTRY)/$(APP_ID)/deployer:$(TAG) \
		$(REGISTRY)/$(APP_ID)/deployer:$(MINOR_VERSION) 2>/dev/null || true
	gcloud container images add-tag --quiet \
		$(REGISTRY)/$(APP_ID)/tester:$(TAG) \
		$(REGISTRY)/$(APP_ID)/tester:$(MINOR_VERSION) 2>/dev/null || true
	$(call print_success,Minor version tags added: $(MINOR_VERSION))

#=============================================================================
# REGISTRY LOGIN
#=============================================================================

.PHONY: registry/login
registry/login:
ifndef TFE_LICENSE
	$(call print_error,TFE_LICENSE environment variable is required)
	@exit 1
endif
	$(call print_notice,Logging into HashiCorp container registry...)
	@echo "$(TFE_LICENSE)" | docker login images.releases.hashicorp.com -u terraform --password-stdin
	$(call print_success,Logged into HashiCorp container registry)

#=============================================================================
# FULL RELEASE PIPELINE
#=============================================================================

.PHONY: release
release: clean app/build gcr/tag-versions
	$(call print_success,Release $(VERSION) complete!)
	@echo ""
	@echo "=== ARTIFACTS ==="
	@echo "TFE Image:      $(REGISTRY)/$(APP_ID):$(TAG) (also tagged $(MAJOR_VERSION), $(MINOR_VERSION))"
	@echo "UBB Image:      $(REGISTRY)/$(APP_ID)/ubbagent:$(TAG) (also tagged $(MAJOR_VERSION), $(MINOR_VERSION))"
	@echo "Deployer:       $(REGISTRY)/$(APP_ID)/deployer:$(TAG) (also tagged $(MAJOR_VERSION), $(MINOR_VERSION))"
	@echo "Tester:         $(REGISTRY)/$(APP_ID)/tester:$(TAG) (also tagged $(MAJOR_VERSION), $(MINOR_VERSION))"
	@echo ""
	@echo "=== NEXT STEPS ==="
	@echo "1. Run mpdev verify: make app/verify"
	@echo "2. Or use release.sh: ./scripts/release.sh --verify"

#=============================================================================
# CLEANUP
#=============================================================================

.PHONY: clean
clean::
	$(call print_notice,Cleaning build artifacts...)
	rm -rf $(BUILD_DIR)

.PHONY: gcr/clean
gcr/clean:
	$(call print_notice,Cleaning GCR images...)
	gcloud container images delete $(REGISTRY)/$(APP_ID):$(TAG) --quiet --force-delete-tags 2>/dev/null || true
	gcloud container images delete $(REGISTRY)/$(APP_ID)/ubbagent:$(TAG) --quiet --force-delete-tags 2>/dev/null || true
	gcloud container images delete $(REGISTRY)/$(APP_ID)/deployer:$(TAG) --quiet --force-delete-tags 2>/dev/null || true
	gcloud container images delete $(REGISTRY)/$(APP_ID)/tester:$(TAG) --quiet --force-delete-tags 2>/dev/null || true

#=============================================================================
# INFO
#=============================================================================

.PHONY: info
info:
	@echo "=== Terraform Enterprise GCP Marketplace (Kubernetes App) ==="
	@echo "APP_ID:               $(APP_ID)"
	@echo "VERSION:              $(VERSION)"
	@echo "MAJOR_VERSION:        $(MAJOR_VERSION)"
	@echo "MINOR_VERSION:        $(MINOR_VERSION)"
	@echo "TFE_UPSTREAM_VERSION: $(TFE_UPSTREAM_VERSION)"
	@echo ""
	@echo "=== Registry ==="
	@echo "REGISTRY:             $(REGISTRY)"
	@echo "TAG:                  $(TAG)"
	@echo "MP_SERVICE_NAME:      $(MP_SERVICE_NAME)"
	@echo ""
	@echo "=== Images ==="
	@echo "  $(REGISTRY)/$(APP_ID):$(TAG)"
	@echo "  $(REGISTRY)/$(APP_ID)/ubbagent:$(TAG)"
	@echo "  $(REGISTRY)/$(APP_ID)/deployer:$(TAG)"
	@echo "  $(REGISTRY)/$(APP_ID)/tester:$(TAG)"
	@echo ""
	@echo "=== Timeouts ==="
	@echo "  VERIFY_WAIT_TIMEOUT: $(VERIFY_WAIT_TIMEOUT)s"
	@echo "  TESTER_TIMEOUT:      $(TESTER_TIMEOUT)s"
