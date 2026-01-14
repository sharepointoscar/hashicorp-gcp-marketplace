# products/terraform-enterprise/Makefile
# HashiCorp Terraform Enterprise (Disk Mode) - GCP Marketplace

# Product configuration
APP_ID := terraform-enterprise
APP_IMAGES := tfe

# TFE version
TFE_VERSION ?= v202501-1

# GCP Marketplace service name (from Partner Portal)
MP_SERVICE_NAME ?= services/terraform-enterprise.endpoints.$(PROJECT_ID).cloud.goog

# Include shared build infrastructure
include ../../shared/Makefile.common
include ../../shared/Makefile.product

# Build all Terraform Enterprise images
.PHONY: app/build
app/build: $(BUILD_DIR)/$(APP_ID)/tfe \
           $(BUILD_DIR)/$(APP_ID)/deployer \
           $(BUILD_DIR)/$(APP_ID)/tester \
           $(BUILD_DIR)/$(APP_ID)/ubbagent

# TFE image
# NOTE: Building this image requires authentication to images.releases.hashicorp.com
# You must be logged in: docker login images.releases.hashicorp.com -u terraform -p <LICENSE_KEY>
$(BUILD_DIR)/$(APP_ID)/tfe: images/tfe/Dockerfile | $(BUILD_DIR)
	$(call print_notice,Building TFE image...)
	@mkdir -p $(BUILD_DIR)/$(APP_ID)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		$(ANNOTATION_FLAG) \
		--build-arg TFE_VERSION="$(TFE_VERSION)" \
		--tag "$(REGISTRY)/$(APP_ID):$(TAG)" \
		-f images/tfe/Dockerfile \
		--push images/tfe
	@touch "$@"
	$(call print_success,TFE image built: $(REGISTRY)/$(APP_ID):$(TAG))

# UBB Agent image (pulled from Google and re-tagged)
$(BUILD_DIR)/$(APP_ID)/ubbagent: | $(BUILD_DIR)
	$(call print_notice,Building UBB agent image...)
	@mkdir -p $(BUILD_DIR)/$(APP_ID)
	docker pull --platform linux/amd64 gcr.io/cloud-marketplace-tools/metering/ubbagent:latest
	docker tag gcr.io/cloud-marketplace-tools/metering/ubbagent:latest $(REGISTRY)/$(APP_ID)/ubbagent:$(TAG)
	docker push $(REGISTRY)/$(APP_ID)/ubbagent:$(TAG)
	@touch "$@"
	$(call print_success,UBB agent image built: $(REGISTRY)/$(APP_ID)/ubbagent:$(TAG))

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

# Clean build artifacts
.PHONY: clean
clean::
	rm -rf $(BUILD_DIR)/$(APP_ID)
