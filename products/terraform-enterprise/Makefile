# products/terraform-enterprise/Makefile
# HashiCorp Terraform Enterprise - GCP Marketplace (Terraform K8s App Model)

APP_ID := terraform-enterprise
VERSION := 1.1.3
# Extract minor version (e.g., 1.1 from 1.1.3) - required by GCP Marketplace
MINOR_VERSION := $(shell echo $(VERSION) | cut -d. -f1,2)
CHART_NAME := terraform-enterprise-chart

# TFE upstream version (update to latest for CVE fixes)
# Note: TFE switched to semantic versioning after v202507-1 (1.0.0+)
TFE_UPSTREAM_VERSION ?= 1.1.3

# Artifact Registry (MUST be us-docker.pkg.dev for Terraform K8s apps)
AR_REGISTRY := us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace
MP_SERVICE_NAME := services/tfe-self-managed.endpoints.ibm-software-mp-project-test.cloud.goog

# Cloud Storage for Terraform module ZIP
TF_MODULE_BUCKET := gs://ibm-software-mp-project-test-tf-modules

# Build directory
BUILD_DIR := .build

# Include shared build infrastructure
include ../../shared/Makefile.common

#=============================================================================
# HELM CHART TARGETS (REQUIRED for Terraform K8s App)
#=============================================================================

.PHONY: helm/lint
helm/lint:
	$(call print_notice,Linting Helm chart...)
	helm lint helm/

.PHONY: helm/package
helm/package: helm/lint
	$(call print_notice,Packaging Helm chart...)
	@mkdir -p $(BUILD_DIR)
	helm package helm/ --version $(VERSION) --destination $(BUILD_DIR)/

.PHONY: helm/push
helm/push: helm/package
	$(call print_notice,Pushing Helm chart to Artifact Registry...)
	helm push $(BUILD_DIR)/$(CHART_NAME)-$(VERSION).tgz oci://$(AR_REGISTRY)
	$(call print_success,Chart pushed: $(AR_REGISTRY)/$(CHART_NAME):$(VERSION))

#=============================================================================
# MINOR VERSION TAGGING (Required by GCP Marketplace)
#=============================================================================

.PHONY: tags/minor
tags/minor:
	$(call print_notice,Adding minor version tags ($(MINOR_VERSION)) to all images...)
	gcloud artifacts docker tags add \
		$(AR_REGISTRY)/$(CHART_NAME):$(VERSION) \
		$(AR_REGISTRY)/$(CHART_NAME):$(MINOR_VERSION) 2>/dev/null || true
	gcloud artifacts docker tags add \
		$(AR_REGISTRY)/tfe:$(VERSION) \
		$(AR_REGISTRY)/tfe:$(MINOR_VERSION) 2>/dev/null || true
	gcloud artifacts docker tags add \
		$(AR_REGISTRY)/ubbagent:$(VERSION) \
		$(AR_REGISTRY)/ubbagent:$(MINOR_VERSION) 2>/dev/null || true
	$(call print_success,Minor version tags added: $(MINOR_VERSION))

#=============================================================================
# IMAGE TARGETS (TFE + UBB only)
#=============================================================================

.PHONY: images/build
images/build: $(BUILD_DIR)/tfe $(BUILD_DIR)/ubbagent

$(BUILD_DIR)/tfe: images/tfe/Dockerfile
	$(call print_notice,Building TFE image...)
	@mkdir -p $(BUILD_DIR)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		--build-arg TFE_VERSION="$(TFE_UPSTREAM_VERSION)" \
		--annotation "com.googleapis.cloudmarketplace.product.service.name=$(MP_SERVICE_NAME)" \
		--tag "$(AR_REGISTRY)/tfe:$(VERSION)" \
		-f images/tfe/Dockerfile \
		--push images/tfe
	@touch $@
	$(call print_success,TFE image built: $(AR_REGISTRY)/tfe:$(VERSION))

$(BUILD_DIR)/ubbagent: images/ubbagent/Dockerfile
	$(call print_notice,Building UBB agent image...)
	@mkdir -p $(BUILD_DIR)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		--annotation "com.googleapis.cloudmarketplace.product.service.name=$(MP_SERVICE_NAME)" \
		--tag "$(AR_REGISTRY)/ubbagent:$(VERSION)" \
		-f images/ubbagent/Dockerfile \
		--push images/ubbagent
	@touch $@
	$(call print_success,UBB agent image built: $(AR_REGISTRY)/ubbagent:$(VERSION))

# Login to HashiCorp registry (requires TFE_LICENSE environment variable)
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
# TERRAFORM MODULE TARGETS
#=============================================================================

.PHONY: terraform/init
terraform/init:
	$(call print_notice,Initializing Terraform...)
	terraform init -backend=false

.PHONY: terraform/validate
terraform/validate: terraform/init
	$(call print_notice,Validating Terraform module...)
	terraform validate

.PHONY: terraform/plan
terraform/plan: terraform/init
	$(call print_notice,Running terraform plan...)
	terraform plan -var-file=marketplace_test.tfvars -var="project_id=ibm-software-mp-project-test"

.PHONY: terraform/package
terraform/package:
	$(call print_notice,Packaging Terraform module ZIP...)
	@mkdir -p $(BUILD_DIR)
	zip -r $(BUILD_DIR)/$(APP_ID)-$(VERSION).zip \
		*.tf modules/ schema.yaml marketplace_test.tfvars README.md \
		-x "*.terraform*" -x "*.tfstate*" -x "$(BUILD_DIR)/*" -x "helm/*" -x "images/*" -x "terraform/*" -x "scripts/*" -x "test-certs/*"

.PHONY: terraform/upload
terraform/upload: terraform/package
	$(call print_notice,Uploading to Cloud Storage...)
	gsutil cp $(BUILD_DIR)/$(APP_ID)-$(VERSION).zip \
		$(TF_MODULE_BUCKET)/$(APP_ID)/$(VERSION)/

#=============================================================================
# VALIDATION (replaces mpdev verify for Terraform K8s apps)
#=============================================================================

.PHONY: validate
validate: helm/lint terraform/validate
	$(call print_success,Validation complete!)

#=============================================================================
# FULL RELEASE PIPELINE
#=============================================================================

.PHONY: release
release: images/build helm/push tags/minor terraform/upload
	$(call print_success,Release $(VERSION) complete!)
	@echo ""
	@echo "=== ARTIFACTS ==="
	@echo "Helm Chart:  $(AR_REGISTRY)/$(CHART_NAME):$(VERSION) (also tagged $(MINOR_VERSION))"
	@echo "TFE Image:   $(AR_REGISTRY)/tfe:$(VERSION) (also tagged $(MINOR_VERSION))"
	@echo "UBB Image:   $(AR_REGISTRY)/ubbagent:$(VERSION) (also tagged $(MINOR_VERSION))"
	@echo "TF Module:   $(TF_MODULE_BUCKET)/$(APP_ID)/$(VERSION)/"
	@echo ""
	@echo "=== PRODUCER PORTAL CONFIGURATION ==="
	@echo "Helm Chart URL: $(AR_REGISTRY)/$(CHART_NAME)"
	@echo "Display tag (minor version): $(MINOR_VERSION)"
	@echo "Module location: $(TF_MODULE_BUCKET)/$(APP_ID)/$(VERSION)/$(APP_ID)-$(VERSION).zip"

#=============================================================================
# CLEANUP
#=============================================================================

.PHONY: clean
clean::
	$(call print_notice,Cleaning build artifacts...)
	rm -rf .terraform/ *.tfstate* terraform/.terraform terraform/*.tfstate*

.PHONY: ar/clean
ar/clean:
	$(call print_notice,Cleaning Artifact Registry...)
	gcloud artifacts docker images delete $(AR_REGISTRY)/tfe:$(VERSION) --quiet 2>/dev/null || true
	gcloud artifacts docker images delete $(AR_REGISTRY)/ubbagent:$(VERSION) --quiet 2>/dev/null || true
	gcloud artifacts docker images delete $(AR_REGISTRY)/$(CHART_NAME):$(VERSION) --quiet 2>/dev/null || true

# Legacy GCR cleanup (from click-to-deploy)
.PHONY: gcr/clean
gcr/clean:
	$(call print_notice,Cleaning all images from GCR...)
	REGISTRY=$(REGISTRY) ./scripts/clean-gcr.sh
	$(call print_success,GCR cleaned)

#=============================================================================
# INFO
#=============================================================================

.PHONY: info
info:
	@echo "=== Terraform Enterprise GCP Marketplace ==="
	@echo "APP_ID:               $(APP_ID)"
	@echo "VERSION:              $(VERSION)"
	@echo "MINOR_VERSION:        $(MINOR_VERSION)"
	@echo "TFE_UPSTREAM_VERSION: $(TFE_UPSTREAM_VERSION)"
	@echo "CHART_NAME:           $(CHART_NAME)"
	@echo ""
	@echo "=== Artifact Registry ==="
	@echo "AR_REGISTRY:          $(AR_REGISTRY)"
	@echo "MP_SERVICE_NAME:      $(MP_SERVICE_NAME)"
	@echo "TF_MODULE_BUCKET:     $(TF_MODULE_BUCKET)"
	@echo ""
	@echo "=== Images to build ==="
	@echo "  $(AR_REGISTRY)/tfe:$(VERSION)"
	@echo "  $(AR_REGISTRY)/ubbagent:$(VERSION)"
	@echo ""
	@echo "=== Helm Chart ==="
	@echo "  $(AR_REGISTRY)/$(CHART_NAME):$(VERSION)"
