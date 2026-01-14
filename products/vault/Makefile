# products/vault/Makefile
# HashiCorp Vault - GCP Marketplace

# Product configuration
APP_ID := vault
APP_IMAGES := vault vault-init

# GCP Marketplace service name (from Partner Portal)
MP_SERVICE_NAME ?= services/vault-enterprise--1-16-ent.endpoints.$(PROJECT_ID).cloud.goog

# Include shared build infrastructure
include ../../shared/Makefile.common
include ../../shared/Makefile.product

# Build all Vault images
.PHONY: app/build
app/build: $(BUILD_DIR)/$(APP_ID)/vault \
           $(BUILD_DIR)/$(APP_ID)/vault-init \
           $(BUILD_DIR)/$(APP_ID)/deployer \
           $(BUILD_DIR)/$(APP_ID)/tester \
           $(BUILD_DIR)/$(APP_ID)/ubbagent

# Vault server image
$(BUILD_DIR)/$(APP_ID)/vault: images/vault/Dockerfile | $(BUILD_DIR)
	$(call print_notice,Building Vault server image...)
	@mkdir -p $(BUILD_DIR)/$(APP_ID)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		$(ANNOTATION_FLAG) \
		--tag "$(REGISTRY)/$(APP_ID):$(TAG)" \
		-f images/vault/Dockerfile \
		--push images/vault
	@touch "$@"
	$(call print_success,Vault image built: $(REGISTRY)/$(APP_ID):$(TAG))

# Vault init container image
$(BUILD_DIR)/$(APP_ID)/vault-init: images/vault-init/Dockerfile | $(BUILD_DIR)
	$(call print_notice,Building Vault init image...)
	@mkdir -p $(BUILD_DIR)/$(APP_ID)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		$(ANNOTATION_FLAG) \
		--tag "$(REGISTRY)/$(APP_ID)/vault-init:$(TAG)" \
		-f images/vault-init/Dockerfile \
		--push images/vault-init
	@touch "$@"
	$(call print_success,Vault-init image built: $(REGISTRY)/$(APP_ID)/vault-init:$(TAG))

# UBB Agent image (pulled from Google and re-tagged)
$(BUILD_DIR)/$(APP_ID)/ubbagent: | $(BUILD_DIR)
	$(call print_notice,Building UBB agent image...)
	@mkdir -p $(BUILD_DIR)/$(APP_ID)
	docker pull --platform linux/amd64 gcr.io/cloud-marketplace-tools/metering/ubbagent:latest
	docker tag gcr.io/cloud-marketplace-tools/metering/ubbagent:latest $(REGISTRY)/$(APP_ID)/ubbagent:$(TAG)
	docker push $(REGISTRY)/$(APP_ID)/ubbagent:$(TAG)
	@touch "$@"
	$(call print_success,UBB agent image built: $(REGISTRY)/$(APP_ID)/ubbagent:$(TAG))
