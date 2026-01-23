# products/boundary/Makefile
# HashiCorp Boundary Enterprise - GCP Marketplace (VM Solution)

APP_ID := boundary-enterprise
VERSION := 0.21.0
BOUNDARY_VERSION := 0.21.0+ent

# GCP Configuration
PROJECT_ID ?= ibm-software-mp-project-test
ZONE ?= us-central1-a

# Marketplace License (from Producer Portal)
MARKETPLACE_LICENSE := projects/ibm-software-mp-project-test/global/licenses/cloud-marketplace-a515e71bc1c469c1-df1ebeb69c0ba664

# Cloud Storage for Terraform module ZIP (Object Versioning must be enabled)
GCS_BUCKET := gs://ibm-software-mp-project-test-tf-modules
GCS_PATH := $(GCS_BUCKET)/$(APP_ID)/$(VERSION)

# VM Image naming - GCP Marketplace format: who-vmOS-image-architecture-date
# Example: hashicorp-ubuntu2204-boundary-x86-64-v0210-20260118
BOUNDARY_VERSION_CLEAN := $(subst +ent,,$(BOUNDARY_VERSION))
BOUNDARY_VERSION_SHORT := v$(subst .,,$(BOUNDARY_VERSION_CLEAN))
BUILD_DATE := $(shell date +%Y%m%d)
IMAGE_NAME := hashicorp-ubuntu2204-boundary-x86-64-$(BOUNDARY_VERSION_SHORT)-$(BUILD_DATE)
IMAGE_FAMILY := boundary-enterprise

# Build directory
BUILD_DIR := .build

# Include shared build infrastructure
include ../../shared/Makefile.common

#=============================================================================
# PACKER VM IMAGE BUILD
#=============================================================================

.PHONY: packer/init
packer/init:
	$(call print_notice,Initializing Packer...)
	cd packer && packer init boundary.pkr.hcl

.PHONY: packer/validate
packer/validate: packer/init
	$(call print_notice,Validating Packer template...)
	cd packer && packer validate \
		-var "project_id=$(PROJECT_ID)" \
		-var "zone=$(ZONE)" \
		-var "boundary_version=$(BOUNDARY_VERSION)" \
		-var "marketplace_license=$(MARKETPLACE_LICENSE)" \
		-var "image_name=$(IMAGE_NAME)" \
		-var "image_family=$(IMAGE_FAMILY)" \
		boundary.pkr.hcl
	$(call print_success,Packer template valid)

.PHONY: packer/build
packer/build: packer/init
	$(call print_notice,Building Boundary VM image...)
	cd packer && packer build \
		-var "project_id=$(PROJECT_ID)" \
		-var "zone=$(ZONE)" \
		-var "boundary_version=$(BOUNDARY_VERSION)" \
		-var "marketplace_license=$(MARKETPLACE_LICENSE)" \
		-var "image_name=$(IMAGE_NAME)" \
		-var "image_family=$(IMAGE_FAMILY)" \
		boundary.pkr.hcl
	$(call print_success,VM image built: $(IMAGE_NAME))
	@echo ""
	@echo "=== Image Details ==="
	@echo "  Name:    $(IMAGE_NAME)"
	@echo "  Family:  $(IMAGE_FAMILY)"
	@echo "  Project: $(PROJECT_ID)"
	@echo "  Path:    projects/$(PROJECT_ID)/global/images/$(IMAGE_NAME)"
	@echo "  License: $(MARKETPLACE_LICENSE)"

.PHONY: image/list
image/list:
	$(call print_notice,Listing Boundary images...)
	gcloud compute images list --project=$(PROJECT_ID) --filter="family=$(IMAGE_FAMILY)" --format="table(name,family,creationTimestamp,licenses)"

.PHONY: image/delete
image/delete:
	$(call print_notice,Deleting image $(IMAGE_NAME)...)
	gcloud compute images delete $(IMAGE_NAME) --project=$(PROJECT_ID) --quiet || true
	$(call print_success,Image deleted)

#=============================================================================
# CFT CLI VALIDATION (Required for VM Solutions)
#=============================================================================

.PHONY: cft/check
cft/check:
	@if ! command -v cft &> /dev/null; then \
		echo -e "$(RED)[ERROR] CFT CLI not found. Install from:$(NC)"; \
		echo "  https://github.com/GoogleCloudPlatform/cloud-foundation-toolkit"; \
		echo ""; \
		echo "Quick install:"; \
		echo "  git clone https://github.com/GoogleCloudPlatform/cloud-foundation-toolkit.git"; \
		echo "  cd cloud-foundation-toolkit && make build"; \
		echo "  sudo cp bin/cft /usr/local/bin/"; \
		exit 1; \
	fi
	$(call print_success,CFT CLI found: $$(cft version 2>/dev/null || echo "installed"))

.PHONY: cft/validate
cft/validate: cft/check
	$(call print_notice,Validating blueprint metadata...)
	cft blueprint metadata -p . -v
	$(call print_success,Metadata validation passed)

.PHONY: cft/generate
cft/generate: cft/check
	$(call print_notice,Generating blueprint metadata...)
	cft blueprint metadata -p . -q -d --nested=false
	$(call print_success,Metadata generated)

#=============================================================================
# TERRAFORM VALIDATION
#=============================================================================

.PHONY: terraform/init
terraform/init:
	$(call print_notice,Initializing Terraform...)
	terraform init -backend=false

.PHONY: terraform/validate
terraform/validate: terraform/init
	$(call print_notice,Validating Terraform module...)
	terraform validate
	$(call print_success,Terraform validation passed)

.PHONY: terraform/plan
terraform/plan: terraform/init
	$(call print_notice,Running terraform plan with test variables...)
	@if [ ! -f marketplace_test.tfvars ]; then \
		echo -e "$(RED)[ERROR] marketplace_test.tfvars not found$(NC)"; \
		echo "Create this file with test values for variables without defaults."; \
		exit 1; \
	fi
	terraform plan -var-file=marketplace_test.tfvars -var="project_id=$(PROJECT_ID)"
	$(call print_success,Terraform plan succeeded)

.PHONY: terraform/apply
terraform/apply: terraform/init
	$(call print_notice,Applying Terraform configuration...)
	@if [ ! -f marketplace_test.tfvars ]; then \
		echo -e "$(RED)[ERROR] marketplace_test.tfvars not found$(NC)"; \
		exit 1; \
	fi
	terraform apply -var-file=marketplace_test.tfvars -var="project_id=$(PROJECT_ID)" -auto-approve
	$(call print_success,Terraform apply succeeded)

.PHONY: terraform/destroy
terraform/destroy: terraform/init
	$(call print_notice,Destroying Terraform resources...)
	@if [ ! -f marketplace_test.tfvars ]; then \
		echo -e "$(RED)[ERROR] marketplace_test.tfvars not found$(NC)"; \
		exit 1; \
	fi
	terraform destroy -var-file=marketplace_test.tfvars -var="project_id=$(PROJECT_ID)" -auto-approve
	$(call print_success,Terraform destroy succeeded)

#=============================================================================
# PACKAGE & UPLOAD
#=============================================================================

.PHONY: package
package: $(BUILD_DIR)/$(APP_ID)-$(VERSION).zip

$(BUILD_DIR)/$(APP_ID)-$(VERSION).zip: main.tf variables.tf outputs.tf versions.tf metadata.yaml metadata.display.yaml README.md marketplace_test.tfvars modules/ test/
	$(call print_notice,Packaging Terraform module ZIP...)
	@mkdir -p $(BUILD_DIR)
	@rm -f $(BUILD_DIR)/$(APP_ID)-$(VERSION).zip
	zip -r $(BUILD_DIR)/$(APP_ID)-$(VERSION).zip \
		main.tf variables.tf outputs.tf versions.tf \
		metadata.yaml metadata.display.yaml \
		README.md \
		marketplace_test.tfvars \
		modules/ \
		test/ \
		packer/ \
		boundary.hclic \
		-x "*.terraform*" -x "*.tfstate*" -x ".build/*" -x ".git*" -x "*.DS_Store" -x "test/terraform.tfvars"
	$(call print_success,Package created: $(BUILD_DIR)/$(APP_ID)-$(VERSION).zip)
	@echo "  Size: $$(du -h $(BUILD_DIR)/$(APP_ID)-$(VERSION).zip | cut -f1)"

.PHONY: upload
upload: package
	$(call print_notice,Uploading to Cloud Storage...)
	@echo "  Destination: $(GCS_PATH)/$(APP_ID)-$(VERSION).zip"
	gsutil cp $(BUILD_DIR)/$(APP_ID)-$(VERSION).zip $(GCS_PATH)/$(APP_ID)-$(VERSION).zip
	$(call print_success,Upload complete)
	@echo ""
	@echo "=== Producer Portal Configuration ==="
	@echo "GCS Path: $(GCS_PATH)/$(APP_ID)-$(VERSION).zip"

.PHONY: gcs/versioning
gcs/versioning:
	$(call print_notice,Enabling Object Versioning on GCS bucket...)
	gsutil versioning set on $(GCS_BUCKET)
	$(call print_success,Object Versioning enabled)

#=============================================================================
# FULL VALIDATION PIPELINE
#=============================================================================

.PHONY: validate
validate: terraform/validate
	@if command -v cft &> /dev/null; then \
		$(MAKE) cft/validate; \
	else \
		echo -e "$(YELLOW)[NOTICE] CFT CLI not installed - skipping metadata validation$(NC)"; \
		echo "  Install CFT CLI to validate metadata.yaml"; \
	fi
	$(call print_success,Validation complete!)

.PHONY: validate/full
validate/full: cft/validate terraform/validate terraform/plan
	$(call print_success,Full validation complete!)

#=============================================================================
# RELEASE PIPELINE
#=============================================================================

.PHONY: release
release: validate package upload
	$(call print_success,Release $(VERSION) complete!)
	@echo ""
	@echo "==========================================="
	@echo "  Boundary Enterprise $(VERSION) Released"
	@echo "==========================================="
	@echo ""
	@echo "=== Artifacts ==="
	@echo "  VM Image: projects/$(PROJECT_ID)/global/images/$(IMAGE_NAME)"
	@echo "  TF Module: $(GCS_PATH)/$(APP_ID)-$(VERSION).zip"
	@echo ""
	@echo "=== Producer Portal Configuration ==="
	@echo "  VM Image:    projects/$(PROJECT_ID)/global/images/$(IMAGE_NAME)"
	@echo "  TF Module:   $(GCS_PATH)/$(APP_ID)-$(VERSION).zip"
	@echo "  License:     $(MARKETPLACE_LICENSE)"
	@echo ""
	@echo "=== Next Steps ==="
	@echo "  1. Build VM image: make packer/build"
	@echo "  2. Go to Producer Portal"
	@echo "  3. Add VM image with license attached"
	@echo "  4. Configure Terraform deployment with GCS path"
	@echo "  5. Click 'Validate' (up to 2 hours)"
	@echo ""

.PHONY: release/full
release/full: packer/build validate package upload
	$(call print_success,Full release $(VERSION) complete (image + terraform)!)

#=============================================================================
# CLEANUP
#=============================================================================

.PHONY: clean
clean::
	$(call print_notice,Cleaning build artifacts...)
	rm -rf $(BUILD_DIR)
	rm -rf .terraform/ *.tfstate* terraform.tfstate.d/

.PHONY: gcs/clean
gcs/clean:
	$(call print_notice,Removing package from GCS...)
	gsutil rm $(GCS_PATH)/$(APP_ID)-$(VERSION).zip 2>/dev/null || true
	$(call print_success,GCS cleanup complete)

#=============================================================================
# INFO & HELP
#=============================================================================

.PHONY: info
info:
	@echo "==========================================="
	@echo "  Boundary Enterprise - GCP Marketplace"
	@echo "==========================================="
	@echo ""
	@echo "=== Configuration ==="
	@echo "  APP_ID:           $(APP_ID)"
	@echo "  VERSION:          $(VERSION)"
	@echo "  BOUNDARY_VERSION: $(BOUNDARY_VERSION)"
	@echo "  PROJECT_ID:       $(PROJECT_ID)"
	@echo ""
	@echo "=== VM Image ==="
	@echo "  IMAGE_NAME:   $(IMAGE_NAME)"
	@echo "  IMAGE_FAMILY: $(IMAGE_FAMILY)"
	@echo "  IMAGE_PATH:   projects/$(PROJECT_ID)/global/images/$(IMAGE_NAME)"
	@echo "  LICENSE:      $(MARKETPLACE_LICENSE)"
	@echo ""
	@echo "=== Cloud Storage ==="
	@echo "  GCS_BUCKET:   $(GCS_BUCKET)"
	@echo "  GCS_PATH:     $(GCS_PATH)"
	@echo ""
	@echo "=== Required IAM Roles ==="
	@echo "  roles/compute.admin"
	@echo "  roles/iam.serviceAccountAdmin"
	@echo "  roles/iam.serviceAccountUser"
	@echo "  roles/cloudsql.admin"
	@echo "  roles/cloudkms.admin"
	@echo "  roles/storage.admin"
	@echo "  roles/secretmanager.secretAccessor"
	@echo "  roles/dns.admin"
	@echo ""
	@echo "=== Required APIs ==="
	@echo "  compute.googleapis.com"
	@echo "  sqladmin.googleapis.com"
	@echo "  cloudkms.googleapis.com"
	@echo "  storage.googleapis.com"
	@echo "  secretmanager.googleapis.com"
	@echo "  dns.googleapis.com"
	@echo "  servicenetworking.googleapis.com"
	@echo "  iam.googleapis.com"
	@echo ""

.PHONY: help
help:
	@echo "Boundary Enterprise - GCP Marketplace Makefile"
	@echo ""
	@echo "=== VM Image Targets ==="
	@echo "  make packer/init      - Initialize Packer"
	@echo "  make packer/validate  - Validate Packer template"
	@echo "  make packer/build     - Build VM image with Marketplace license"
	@echo "  make image/list       - List Boundary images in project"
	@echo "  make image/delete     - Delete the current version image"
	@echo ""
	@echo "=== Validation Targets ==="
	@echo "  make cft/validate     - Validate metadata with CFT CLI"
	@echo "  make terraform/validate - Validate Terraform module"
	@echo "  make terraform/plan   - Run terraform plan with test vars"
	@echo "  make terraform/apply  - Apply Terraform configuration"
	@echo "  make terraform/destroy - Destroy Terraform resources"
	@echo "  make validate         - Run all validations (cft + terraform)"
	@echo "  make validate/full    - Run all validations including plan"
	@echo ""
	@echo "=== Build & Release Targets ==="
	@echo "  make package          - Create ZIP package"
	@echo "  make upload           - Upload package to GCS"
	@echo "  make release          - Release TF module (validate + package + upload)"
	@echo "  make release/full     - Full release (image + TF module)"
	@echo ""
	@echo "=== Utility Targets ==="
	@echo "  make cft/generate     - Generate metadata files"
	@echo "  make gcs/versioning   - Enable GCS Object Versioning"
	@echo "  make clean            - Clean local build artifacts"
	@echo "  make gcs/clean        - Remove package from GCS"
	@echo "  make info             - Show configuration & required IAM roles"
	@echo "  make help             - Show this help"
	@echo ""
	@echo "=== Required Environment ==="
	@echo "  PROJECT_ID            - GCP project (default: $(PROJECT_ID))"
	@echo "  ZONE                  - GCP zone for image build (default: $(ZONE))"
	@echo "  marketplace_test.tfvars - Test variables file"
	@echo ""
