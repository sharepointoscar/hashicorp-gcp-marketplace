# products/consul/Makefile
# HashiCorp Consul Enterprise - GCP Marketplace Click-to-Deploy

APP_ID := consul
VERSION := 1.21.7
MINOR_VERSION := $(shell echo $(VERSION) | cut -d. -f1,2)

# Consul upstream version (use full version for specific patch)
CONSUL_VERSION := 1.21.7

# Artifact Registry (same project as TFE)
AR_REGISTRY := us-docker.pkg.dev/ibm-software-mp-project-test/consul-marketplace
MP_SERVICE_NAME := services/consul-enterprise-1-21.endpoints.ibm-software-mp-project-test.cloud.goog

# License file (auto-detect .hclic file in current directory)
LICENSE_FILE := $(wildcard *.hclic)

# Build directory
BUILD_DIR := .build

# Include shared build infrastructure
include ../../shared/Makefile.common

#=============================================================================
# APPLICATION IMAGES
#=============================================================================

.PHONY: images/build
images/build: $(BUILD_DIR)/consul $(BUILD_DIR)/ubbagent

$(BUILD_DIR)/consul: images/consul/Dockerfile
	$(call print_notice,Building Consul Enterprise image...)
	@mkdir -p $(BUILD_DIR)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		--build-arg CONSUL_VERSION="$(CONSUL_VERSION)" \
		--annotation "com.googleapis.cloudmarketplace.product.service.name=$(MP_SERVICE_NAME)" \
		--tag "$(AR_REGISTRY)/consul:$(VERSION)" \
		-f images/consul/Dockerfile \
		--push images/consul
	@touch "$@"
	$(call print_success,Consul image built: $(AR_REGISTRY)/consul:$(VERSION))

$(BUILD_DIR)/ubbagent: images/ubbagent/Dockerfile
	$(call print_notice,Building UBB agent image...)
	@mkdir -p $(BUILD_DIR)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		--annotation "com.googleapis.cloudmarketplace.product.service.name=$(MP_SERVICE_NAME)" \
		--tag "$(AR_REGISTRY)/ubbagent:$(VERSION)" \
		-f images/ubbagent/Dockerfile \
		--push images/ubbagent
	@touch "$@"
	$(call print_success,UBB agent image built: $(AR_REGISTRY)/ubbagent:$(VERSION))

#=============================================================================
# DEPLOYER IMAGE (Click-to-Deploy)
#=============================================================================

$(BUILD_DIR)/deployer: deployer/Dockerfile schema.yaml manifest/*.template apptest/deployer/schema.yaml apptest/deployer/manifest/*.template
	$(call print_notice,Building deployer image...)
	@mkdir -p $(BUILD_DIR)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		--annotation "com.googleapis.cloudmarketplace.product.service.name=$(MP_SERVICE_NAME)" \
		--tag "$(AR_REGISTRY)/deployer:$(VERSION)" \
		-f deployer/Dockerfile \
		--push .
	@touch "$@"
	$(call print_success,Deployer image built: $(AR_REGISTRY)/deployer:$(VERSION))

#=============================================================================
# TESTER IMAGE
#=============================================================================

$(BUILD_DIR)/tester: apptest/deployer/Dockerfile
	$(call print_notice,Building tester image...)
	@mkdir -p $(BUILD_DIR)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		--annotation "com.googleapis.cloudmarketplace.product.service.name=$(MP_SERVICE_NAME)" \
		--tag "$(AR_REGISTRY)/tester:$(VERSION)" \
		-f apptest/deployer/Dockerfile \
		--push apptest/deployer
	@touch "$@"
	$(call print_success,Tester image built: $(AR_REGISTRY)/tester:$(VERSION))

#=============================================================================
# FULL BUILD
#=============================================================================

.PHONY: app/build
app/build: images/build $(BUILD_DIR)/deployer $(BUILD_DIR)/tester
	$(call print_success,All images built for $(APP_ID))

#=============================================================================
# MINOR VERSION TAGGING (Required by GCP Marketplace)
#=============================================================================

.PHONY: tags/minor
tags/minor:
	$(call print_notice,Adding minor version tags ($(MINOR_VERSION)) to all images...)
	gcloud artifacts docker tags add \
		$(AR_REGISTRY)/consul:$(VERSION) \
		$(AR_REGISTRY)/consul:$(MINOR_VERSION) 2>/dev/null || true
	gcloud artifacts docker tags add \
		$(AR_REGISTRY)/ubbagent:$(VERSION) \
		$(AR_REGISTRY)/ubbagent:$(MINOR_VERSION) 2>/dev/null || true
	gcloud artifacts docker tags add \
		$(AR_REGISTRY)/deployer:$(VERSION) \
		$(AR_REGISTRY)/deployer:$(MINOR_VERSION) 2>/dev/null || true
	gcloud artifacts docker tags add \
		$(AR_REGISTRY)/tester:$(VERSION) \
		$(AR_REGISTRY)/tester:$(MINOR_VERSION) 2>/dev/null || true
	$(call print_success,Minor version tags added: $(MINOR_VERSION))

#=============================================================================
# RELEASE (build + tag minor version)
#=============================================================================

.PHONY: release
release: clean app/build tags/minor
	$(call print_success,Release $(VERSION) complete for $(APP_ID)!)
	@echo ""
	@echo "=== Images ==="
	@echo "  $(AR_REGISTRY)/consul:$(VERSION) (also tagged $(MINOR_VERSION))"
	@echo "  $(AR_REGISTRY)/ubbagent:$(VERSION) (also tagged $(MINOR_VERSION))"
	@echo "  $(AR_REGISTRY)/deployer:$(VERSION) (also tagged $(MINOR_VERSION))"
	@echo "  $(AR_REGISTRY)/tester:$(VERSION) (also tagged $(MINOR_VERSION))"

#=============================================================================
# ARTIFACT REGISTRY CLEANUP
#=============================================================================

.PHONY: ar/clean
ar/clean:
	$(call print_notice,Cleaning Artifact Registry images for $(APP_ID)...)
	-gcloud artifacts docker images delete "$(AR_REGISTRY)/consul:$(VERSION)" --quiet 2>/dev/null || true
	-gcloud artifacts docker images delete "$(AR_REGISTRY)/ubbagent:$(VERSION)" --quiet 2>/dev/null || true
	-gcloud artifacts docker images delete "$(AR_REGISTRY)/deployer:$(VERSION)" --quiet 2>/dev/null || true
	-gcloud artifacts docker images delete "$(AR_REGISTRY)/tester:$(VERSION)" --quiet 2>/dev/null || true
	$(call print_success,Artifact Registry images cleaned)

.PHONY: ar/clean-all
ar/clean-all:
	$(call print_notice,Cleaning ALL Artifact Registry images for $(APP_ID)...)
	@# Delete all images in each repository
	-for digest in $$(gcloud artifacts docker images list "$(AR_REGISTRY)/consul" --format='get(version)' 2>/dev/null); do \
		gcloud artifacts docker images delete "$(AR_REGISTRY)/consul@$$digest" --delete-tags --quiet 2>/dev/null || true; \
	done
	-for digest in $$(gcloud artifacts docker images list "$(AR_REGISTRY)/ubbagent" --format='get(version)' 2>/dev/null); do \
		gcloud artifacts docker images delete "$(AR_REGISTRY)/ubbagent@$$digest" --delete-tags --quiet 2>/dev/null || true; \
	done
	-for digest in $$(gcloud artifacts docker images list "$(AR_REGISTRY)/deployer" --format='get(version)' 2>/dev/null); do \
		gcloud artifacts docker images delete "$(AR_REGISTRY)/deployer@$$digest" --delete-tags --quiet 2>/dev/null || true; \
	done
	-for digest in $$(gcloud artifacts docker images list "$(AR_REGISTRY)/tester" --format='get(version)' 2>/dev/null); do \
		gcloud artifacts docker images delete "$(AR_REGISTRY)/tester@$$digest" --delete-tags --quiet 2>/dev/null || true; \
	done
	$(call print_success,All Artifact Registry images cleaned for $(APP_ID))

#=============================================================================
# HASHICORP REGISTRY LOGIN
#=============================================================================

.PHONY: registry/login
registry/login:
	@if [ -z "$(LICENSE_FILE)" ]; then \
		echo -e "$(RED)[ERROR] No .hclic license file found in current directory$(NC)"; \
		echo "Place your Consul Enterprise license file (*.hclic) in this directory"; \
		exit 1; \
	fi
	$(call print_notice,Reading license from $(LICENSE_FILE)...)
	$(call print_notice,Logging into HashiCorp container registry...)
	@cat "$(LICENSE_FILE)" | docker login images.releases.hashicorp.com -u terraform --password-stdin
	$(call print_success,Logged into HashiCorp container registry)

#=============================================================================
# VALIDATION
#=============================================================================

# Direct mpdev targets (for quick iteration)
.PHONY: app/verify
app/verify:
	@if [ -z "$(LICENSE_FILE)" ]; then \
		echo -e "$(RED)[ERROR] No .hclic license file found$(NC)"; \
		exit 1; \
	fi
	$(call print_notice,Running mpdev verify for $(APP_ID)...)
	mpdev verify \
		--deployer="$(AR_REGISTRY)/deployer:$(VERSION)" \
		--parameters='{"consulLicense": "'"$$(cat $(LICENSE_FILE))"'"}'

.PHONY: app/install
app/install:
	@if [ -z "$(LICENSE_FILE)" ]; then \
		echo -e "$(RED)[ERROR] No .hclic license file found$(NC)"; \
		exit 1; \
	fi
	$(call print_notice,Running mpdev install for $(APP_ID)...)
	mpdev install \
		--deployer="$(AR_REGISTRY)/deployer:$(VERSION)" \
		--parameters='{"consulLicense": "'"$$(cat $(LICENSE_FILE))"'"}'

#=============================================================================
# INFO
#=============================================================================

.PHONY: info
info:
	@echo "=== Consul Enterprise GCP Marketplace ==="
	@echo "APP_ID:          $(APP_ID)"
	@echo "VERSION:         $(VERSION)"
	@echo "MINOR_VERSION:   $(MINOR_VERSION)"
	@echo "CONSUL_VERSION:  $(CONSUL_VERSION)"
	@echo "AR_REGISTRY:     $(AR_REGISTRY)"
	@echo "MP_SERVICE_NAME: $(MP_SERVICE_NAME)"
	@echo "LICENSE_FILE:    $(if $(LICENSE_FILE),$(LICENSE_FILE),<not found>)"
	@echo ""
	@echo "=== Images ==="
	@echo "  $(AR_REGISTRY)/consul:$(VERSION)"
	@echo "  $(AR_REGISTRY)/ubbagent:$(VERSION)"
	@echo "  $(AR_REGISTRY)/deployer:$(VERSION)"
	@echo "  $(AR_REGISTRY)/tester:$(VERSION)"
