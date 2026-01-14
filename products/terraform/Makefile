# products/terraform/Makefile
# HashiCorp Terraform Cloud Agent - GCP Marketplace

# Product configuration
APP_ID := terraform
APP_IMAGES := tfc-agent

# GCP Marketplace service name (from Partner Portal)
MP_SERVICE_NAME ?= services/terraform-cloud-agent.endpoints.$(PROJECT_ID).cloud.goog

# Include shared build infrastructure
include ../../shared/Makefile.common
include ../../shared/Makefile.product

# Build all Terraform images
.PHONY: app/build
app/build: $(BUILD_DIR)/$(APP_ID)/tfc-agent \
           $(BUILD_DIR)/$(APP_ID)/deployer \
           $(BUILD_DIR)/$(APP_ID)/tester \
           $(BUILD_DIR)/$(APP_ID)/ubbagent

# TFC Agent image
$(BUILD_DIR)/$(APP_ID)/tfc-agent: images/tfc-agent/Dockerfile | $(BUILD_DIR)
	$(call print_notice,Building TFC Agent image...)
	@mkdir -p $(BUILD_DIR)/$(APP_ID)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		$(ANNOTATION_FLAG) \
		--tag "$(REGISTRY)/$(APP_ID):$(TAG)" \
		-f images/tfc-agent/Dockerfile \
		--push images/tfc-agent
	@touch "$@"
	$(call print_success,TFC Agent image built: $(REGISTRY)/$(APP_ID):$(TAG))

# UBB Agent image (pulled from Google and re-tagged)
$(BUILD_DIR)/$(APP_ID)/ubbagent: | $(BUILD_DIR)
	$(call print_notice,Building UBB agent image...)
	@mkdir -p $(BUILD_DIR)/$(APP_ID)
	docker pull --platform linux/amd64 gcr.io/cloud-marketplace-tools/metering/ubbagent:latest
	docker tag gcr.io/cloud-marketplace-tools/metering/ubbagent:latest $(REGISTRY)/$(APP_ID)/ubbagent:$(TAG)
	docker push $(REGISTRY)/$(APP_ID)/ubbagent:$(TAG)
	@touch "$@"
	$(call print_success,UBB agent image built: $(REGISTRY)/$(APP_ID)/ubbagent:$(TAG))
