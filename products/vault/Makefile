# products/vault/Makefile
# HashiCorp Vault Enterprise - GCP Marketplace Click-to-Deploy

APP_ID := vault
VERSION := 1.21.0
VAULT_VERSION := 1.21.0
MINOR_VERSION := $(shell echo $(VERSION) | cut -d. -f1,2)
MAJOR_VERSION := $(shell echo $(VERSION) | cut -d. -f1)

# Artifact Registry
AR_REGISTRY := us-docker.pkg.dev/ibm-software-mp-project-test/vault-marketplace
MP_SERVICE_NAME := services/vault-enterprise--1-16-ent.endpoints.ibm-software-mp-project-test.cloud.goog

# License file (auto-detect .hclic file in current directory)
# Vault Enterprise images are on Docker Hub (no registry login needed)
# License is only needed at runtime via VAULT_LICENSE env var
LICENSE_FILE := $(wildcard *.hclic)

# Build configuration
PLATFORM := linux/amd64
BUILD_DIR := .build
DOCKER_BUILD_FLAGS := --platform $(PLATFORM) \
    --provenance=false \
    --sbom=false \
    --no-cache \
    --pull

# Colors
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

define print_notice
	@echo -e "$(YELLOW)[NOTICE] $1$(NC)"
endef

define print_success
	@echo -e "$(GREEN)[OK] $1$(NC)"
endef

define print_error
	@echo -e "$(RED)[ERROR] $1$(NC)"
endef

#=============================================================================
# APPLICATION IMAGES
#=============================================================================

.PHONY: images/build
images/build: $(BUILD_DIR)/vault $(BUILD_DIR)/vault-init $(BUILD_DIR)/ubbagent

$(BUILD_DIR)/vault: images/vault/Dockerfile
	$(call print_notice,Building Vault Enterprise image...)
	@mkdir -p $(BUILD_DIR)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		--build-arg VAULT_VERSION=$(VAULT_VERSION) \
		--annotation "com.googleapis.cloudmarketplace.product.service.name=$(MP_SERVICE_NAME)" \
		--tag "$(AR_REGISTRY)/vault:$(VERSION)" \
		-f images/vault/Dockerfile \
		--push images/vault
	@touch "$@"
	$(call print_success,Vault image built: $(AR_REGISTRY)/vault:$(VERSION))

$(BUILD_DIR)/vault-init: images/vault-init/Dockerfile
	$(call print_notice,Building Vault init image...)
	@mkdir -p $(BUILD_DIR)
	docker buildx build $(DOCKER_BUILD_FLAGS) \
		--build-arg VAULT_VERSION=$(VAULT_VERSION) \
		--annotation "com.googleapis.cloudmarketplace.product.service.name=$(MP_SERVICE_NAME)" \
		--tag "$(AR_REGISTRY)/vault-init:$(VERSION)" \
		-f images/vault-init/Dockerfile \
		--push images/vault-init
	@touch "$@"
	$(call print_success,Vault-init image built: $(AR_REGISTRY)/vault-init:$(VERSION))

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

$(BUILD_DIR)/tester: apptest/deployer/Dockerfile apptest/deployer/schema.yaml apptest/deployer/manifest/*.template
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
	$(call print_notice,Adding major ($(MAJOR_VERSION)) and minor ($(MINOR_VERSION)) version tags to all images...)
	@for img in vault vault-init ubbagent deployer tester; do \
		gcloud artifacts docker tags add \
			$(AR_REGISTRY)/$$img:$(VERSION) \
			$(AR_REGISTRY)/$$img:$(MINOR_VERSION) 2>/dev/null || true; \
		gcloud artifacts docker tags add \
			$(AR_REGISTRY)/$$img:$(VERSION) \
			$(AR_REGISTRY)/$$img:$(MAJOR_VERSION) 2>/dev/null || true; \
	done
	$(call print_success,Version tags added: $(MAJOR_VERSION) and $(MINOR_VERSION))

#=============================================================================
# RELEASE (build + tag minor version)
#=============================================================================

.PHONY: release
release: clean app/build tags/minor
	$(call print_success,Release $(VERSION) complete for $(APP_ID)!)
	@echo ""
	@echo "=== Images ==="
	@echo "  $(AR_REGISTRY)/vault:$(VERSION) (also tagged $(MINOR_VERSION), $(MAJOR_VERSION))"
	@echo "  $(AR_REGISTRY)/vault-init:$(VERSION) (also tagged $(MINOR_VERSION), $(MAJOR_VERSION))"
	@echo "  $(AR_REGISTRY)/ubbagent:$(VERSION) (also tagged $(MINOR_VERSION), $(MAJOR_VERSION))"
	@echo "  $(AR_REGISTRY)/deployer:$(VERSION) (also tagged $(MINOR_VERSION), $(MAJOR_VERSION))"
	@echo "  $(AR_REGISTRY)/tester:$(VERSION) (also tagged $(MINOR_VERSION), $(MAJOR_VERSION))"

#=============================================================================
# ARTIFACT REGISTRY CLEANUP
#=============================================================================

.PHONY: ar/clean
ar/clean:
	$(call print_notice,Cleaning Artifact Registry images for $(APP_ID)...)
	-gcloud artifacts docker images delete "$(AR_REGISTRY)/vault:$(VERSION)" --quiet 2>/dev/null || true
	-gcloud artifacts docker images delete "$(AR_REGISTRY)/vault-init:$(VERSION)" --quiet 2>/dev/null || true
	-gcloud artifacts docker images delete "$(AR_REGISTRY)/ubbagent:$(VERSION)" --quiet 2>/dev/null || true
	-gcloud artifacts docker images delete "$(AR_REGISTRY)/deployer:$(VERSION)" --quiet 2>/dev/null || true
	-gcloud artifacts docker images delete "$(AR_REGISTRY)/tester:$(VERSION)" --quiet 2>/dev/null || true
	$(call print_success,Artifact Registry images cleaned)

.PHONY: ar/clean-all
ar/clean-all:
	$(call print_notice,Cleaning ALL Artifact Registry images for $(APP_ID)...)
	-for digest in $$(gcloud artifacts docker images list "$(AR_REGISTRY)/vault" --format='get(version)' 2>/dev/null); do \
		gcloud artifacts docker images delete "$(AR_REGISTRY)/vault@$$digest" --delete-tags --quiet 2>/dev/null || true; \
	done
	-for digest in $$(gcloud artifacts docker images list "$(AR_REGISTRY)/vault-init" --format='get(version)' 2>/dev/null); do \
		gcloud artifacts docker images delete "$(AR_REGISTRY)/vault-init@$$digest" --delete-tags --quiet 2>/dev/null || true; \
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
# VALIDATION
#=============================================================================

.PHONY: app/verify
app/verify:
	@if [ -z "$(LICENSE_FILE)" ]; then \
		echo -e "$(RED)[ERROR] No .hclic license file found$(NC)"; \
		echo "Place your Vault Enterprise license (*.hclic) in this directory"; \
		exit 1; \
	fi
	$(call print_notice,Running mpdev verify for $(APP_ID)...)
	mpdev verify \
		--deployer="$(AR_REGISTRY)/deployer:$(VERSION)" \
		--parameters='{"vaultLicense": "'"$$(cat $(LICENSE_FILE))"'"}'

.PHONY: app/install
app/install:
	@if [ -z "$(LICENSE_FILE)" ]; then \
		echo -e "$(RED)[ERROR] No .hclic license file found$(NC)"; \
		echo "Place your Vault Enterprise license (*.hclic) in this directory"; \
		exit 1; \
	fi
	$(call print_notice,Running mpdev install for $(APP_ID)...)
	@kubectl create ns vault-test 2>/dev/null || true
	@kubectl apply -f - <<< '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"vault-reporting-secret","namespace":"vault-test"},"type":"Opaque","data":{}}' 2>/dev/null || true
	mpdev install \
		--deployer="$(AR_REGISTRY)/deployer:$(VERSION)" \
		--parameters='{"name": "vault", "namespace": "vault-test", "replicas": 1, "reportingSecret": "vault-reporting-secret", "vaultLicense": "'"$$(cat $(LICENSE_FILE))"'"}'

#=============================================================================
# CLEANUP
#=============================================================================

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

.PHONY: ns/clean
ns/clean:
	$(call print_notice,Cleaning up vault test namespaces...)
	@for ns in $$(kubectl get ns -o name 2>/dev/null | grep -E "vault-|apptest-" | cut -d'/' -f2); do \
		echo "  Cleaning namespace: $$ns"; \
		kubectl delete application --all -n "$$ns" --wait=false 2>/dev/null || true; \
		kubectl delete statefulset --all -n "$$ns" --wait=false 2>/dev/null || true; \
		kubectl delete deploy --all -n "$$ns" --wait=false 2>/dev/null || true; \
		kubectl delete job --all -n "$$ns" --wait=false 2>/dev/null || true; \
		kubectl delete pvc --all -n "$$ns" 2>/dev/null || true; \
		kubectl delete ns "$$ns" 2>/dev/null || true; \
	done
	@echo "  Cleaning orphaned PVs..."
	@for pv in $$(kubectl get pv -o json 2>/dev/null | python3 -c "import sys,json; [print(i['metadata']['name']) for i in json.load(sys.stdin).get('items',[]) if i.get('status',{}).get('phase')=='Released' or (i.get('spec',{}).get('claimRef',{}).get('namespace','') and any(x in i['spec']['claimRef']['namespace'] for x in ['vault-','apptest-']))]" 2>/dev/null); do \
		echo "  Deleting orphaned PV: $$pv"; \
		kubectl delete pv "$$pv" 2>/dev/null || true; \
	done
	$(call print_success,Test namespaces and resources cleaned)

#=============================================================================
# INFO
#=============================================================================

.PHONY: info
info:
	@echo "=== Vault Enterprise GCP Marketplace ==="
	@echo "APP_ID:          $(APP_ID)"
	@echo "VERSION:         $(VERSION)"
	@echo "MINOR_VERSION:   $(MINOR_VERSION)"
	@echo "AR_REGISTRY:     $(AR_REGISTRY)"
	@echo "MP_SERVICE_NAME: $(MP_SERVICE_NAME)"
	@echo "LICENSE_FILE:    $(if $(LICENSE_FILE),$(LICENSE_FILE),<not found>)"
	@echo ""
	@echo "=== Images ==="
	@echo "  $(AR_REGISTRY)/vault:$(VERSION)"
	@echo "  $(AR_REGISTRY)/vault-init:$(VERSION)"
	@echo "  $(AR_REGISTRY)/ubbagent:$(VERSION)"
	@echo "  $(AR_REGISTRY)/deployer:$(VERSION)"
	@echo "  $(AR_REGISTRY)/tester:$(VERSION)"
