# Makefile - HashiCorp GCP Marketplace Monorepo
# Root orchestration for all products

# Default product (can be overridden: make PRODUCT=consul build)
PRODUCT ?= vault

# List of all products
PRODUCTS := vault consul nomad terraform

# Help target
.PHONY: help
help:
	@echo "HashiCorp GCP Marketplace Monorepo"
	@echo ""
	@echo "Usage:"
	@echo "  make PRODUCT=<name> <target>    Run target for specific product"
	@echo "  make <target>                   Run target for default product ($(PRODUCT))"
	@echo ""
	@echo "Products: $(PRODUCTS)"
	@echo ""
	@echo "Targets:"
	@echo "  build          Build all images for a product"
	@echo "  verify         Run mpdev verify for a product"
	@echo "  validate       Run full validation script for a product"
	@echo "  clean          Clean build artifacts for a product"
	@echo "  build-all      Build all products"
	@echo "  clean-all      Clean all products"
	@echo ""
	@echo "Examples:"
	@echo "  make PRODUCT=vault REGISTRY=gcr.io/my-project TAG=1.21.0 build"
	@echo "  make PRODUCT=consul validate"
	@echo "  make build-all"

# Build a specific product
.PHONY: build
build:
	@echo "Building $(PRODUCT)..."
	$(MAKE) -C products/$(PRODUCT) app/build

# Verify a specific product
.PHONY: verify
verify:
	@echo "Verifying $(PRODUCT)..."
	$(MAKE) -C products/$(PRODUCT) app/verify

# Validate a specific product (full validation script)
.PHONY: validate
validate:
	@echo "Validating $(PRODUCT)..."
	./shared/scripts/validate-marketplace.sh $(PRODUCT)

# Clean a specific product
.PHONY: clean
clean:
	@echo "Cleaning $(PRODUCT)..."
	$(MAKE) -C products/$(PRODUCT) clean

# Build all products
.PHONY: build-all
build-all:
	@for product in $(PRODUCTS); do \
		if [ -f "products/$$product/Makefile" ]; then \
			echo "Building $$product..."; \
			$(MAKE) -C products/$$product app/build || exit 1; \
		else \
			echo "Skipping $$product (no Makefile)"; \
		fi \
	done

# Clean all products
.PHONY: clean-all
clean-all:
	@for product in $(PRODUCTS); do \
		if [ -f "products/$$product/Makefile" ]; then \
			$(MAKE) -C products/$$product clean; \
		fi \
	done

# Initialize submodules
.PHONY: init
init:
	git submodule sync --recursive
	git submodule update --recursive --init --force
