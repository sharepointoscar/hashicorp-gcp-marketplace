# Coding Conventions

**Analysis Date:** 2025-02-24

## Naming Patterns

**Files:**
- Shell scripts: lowercase with hyphens, e.g., `validate-marketplace.sh`, `install-boundary.sh`, `deploy-with-logging.sh`
- Makefiles: `Makefile` (no suffix) for product-specific files; `Makefile.common` and `Makefile.product` for shared infrastructure
- Terraform files: lowercase with hyphens in names, e.g., `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
- Configuration: `schema.yaml`, `product.yaml`, `metadata.yaml`, `metadata.display.yaml`
- Documentation: uppercase markdown, e.g., `README.md`, `CLAUDE.md`

**Functions in Shell:**
- Lowercase with underscores: `print_step()`, `print_success()`, `print_error()`, `print_warning()`, `docker_build_mp()`, `load_product_config()`, `check_prerequisites()`
- Helper prefix for internal functions: functions like `strip_colors()`, `cleanup_all_resources()` that perform internal work
- Naming convention reflects purpose clearly: verb-first pattern (e.g., `scan_image()`, `run_validation()`, `collect_logs()`)

**Variables in Shell:**
- Uppercase with underscores for constants: `RED='\033[0;31m'`, `DOCKER_BUILD_FLAGS`, `PLATFORM`, `BUILD_DIR`
- Lowercase with underscores for runtime variables: `product_dir`, `registry`, `tag`, `license_file`
- Consistent naming across shared library and product scripts

**Terraform Variables:**
- Lowercase with underscores: `project_id`, `region`, `friendly_name_prefix`, `boundary_fqdn`
- Boolean flags: `enable_session_recording`, `create_proxy_subnet`, `create_cloud_dns_record`
- Collection prefixes for related variables: `tls_cert_path`, `tls_key_path`, `tls_ca_bundle_path`
- Naming reflects purpose: `goog_cm_deployment_name` (GCP Marketplace deployment), `vpc_project_id` (explicit scope)

## Code Style

**Formatting:**
- No dedicated code formatter (no `.prettierrc`, `.eslintrc`, or `biome.json`)
- Shell scripts use `set -euo pipefail` for strict error handling
- Terraform modules follow HCL2 conventions with 2-space indentation
- Makefile recipes use tab indentation (required by make)

**Linting:**
- No active linting configuration
- Terraform validation: `terraform validate` (standard HCL syntax)
- CFT validation: `cft blueprint metadata -p . -v` (GCP Marketplace metadata)
- Shell validation: implicit via `set -e` (fail on error) and `set -u` (fail on undefined variable)

**Line Length:**
- No enforced line length limit
- Comment headers use 80-character separators for readability: `#------------------------------------------------------------------------------`
- Long commands split across lines using backslash continuation in Makefiles
- Terraform blocks formatted with clear indentation, typically 4-space grouped sections

**Comments:**
- License headers: SPDX format at file top: `# Copyright (c) HashiCorp, Inc. / # SPDX-License-Identifier: MPL-2.0`
- Section separators: 78-character dashed lines with descriptive titles
- Inline comments: Explain why, not what (assume reader understands code syntax)
- Documentation comments in Terraform: `description` fields on variables and outputs (not separate docstrings)

## Import Organization

**Shell Scripts:**
- No formal imports; instead source external functions: `source "$SHARED_DIR/scripts/lib/common.sh"`
- Sourced files placed early: script setup → source functions → main logic
- Example from `validate-marketplace.sh`: Load paths → source common library → parse args → main execution

**Terraform Modules:**
- No explicit imports; instead use `module` and `data` blocks
- Module sourcing follows pattern: `source = "./modules/<module-name>"` (local) or `source = "git::https://..."` (remote)
- Variables passed to modules are explicit in `module` blocks (see `main.tf` modules/controller, modules/prerequisites)

**Makefile Includes:**
- Shared infrastructure included via: `include ../../shared/Makefile.common`
- Product-specific Makefile includes shared rules without `include` but references them via variable inheritance

## Error Handling

**Patterns:**
- Shell scripts use `set -e` to exit on first error; `set -u` to error on undefined variables
- All bash scripts begin with `#!/usr/bin/env bash` (not `/bin/bash`) for portability
- Exit codes checked via `$?` when needed for conditional cleanup: `if make terraform/apply 2>&1 | tee "$log_file"; then ...`
- Error messages to stderr: functions use `print_error()` which uses standard echo (not redirected)
- Try-catch pattern via `|| exit 1` for critical phases or `|| true` for optional cleanup

**Error Message Convention:**
```bash
print_error "Some operation failed"
print_warning "This might be an issue but continuing"
print_success "Operation completed successfully"
```

**Terraform Error Handling:**
- `validation` blocks in variables for input validation: see `friendly_name_prefix` validation in `variables.tf`
- Conditions checked before resource creation: `count = var.create_proxy_subnet ? 1 : 0`
- Error messages in validation blocks are descriptive: "Value must be less than 13 characters."

## Logging

**Framework:**
- Shell: Custom functions with colored output (no external logging library)
- Terraform: Native logging via `terraform output` and `terraform apply` stdout
- Makefile: Print functions from `Makefile.common` for consistency

**Patterns:**
- Log to stdout, tee to file: `make validate/full 2>&1 | tee "$log_file"`
- Phase-based logging: Each deployment phase writes to timestamped log file in `logs/deployment-YYYYMMDD-HHMMSS/` directory
- Clean logs: ANSI color codes stripped via `sed 's/\x1b\[[0-9;]*m//g'` for text editor readability
- Duration tracking: Store phase durations in hidden files (`.phase1-duration`, etc.) for summary generation

**Output Levels:**
```bash
print_step "1" "Verifying Prerequisites"          # Phase indicators
print_notice "[NOTICE] Building deployer image"   # Build/operation progress
print_success "[OK] All images built"             # Completion status
print_warning "[WARN] Some namespaces terminating" # Advisory warnings
print_error "[ERROR] No license file found"       # Failures
```

## Comments

**When to Comment:**
- License header on every file: `# SPDX-License-Identifier: MPL-2.0`
- Section separators to organize large files into logical blocks
- Complex logic: Explain the "why" not the "what"
- Non-obvious variable choices: `# Marketplace deployment name if provided, otherwise use friendly_name_prefix`
- Configuration decisions: Comment why a default was chosen or a workaround is needed

**JSDoc/TSDoc:**
- Not used (codebase is primarily Bash, Make, Terraform, and HCL)
- Terraform variables use `description` fields instead of docstrings
- Bash functions have inline comments or are self-documenting via naming

**Documentation Blocks:**
- Terraform module headers explain purpose and what resources are created
- Example from `main.tf`:
  ```hcl
  #------------------------------------------------------------------------------
  # Prerequisites - Creates secrets, TLS certs, and database password
  #------------------------------------------------------------------------------

  module "prerequisites" {
  ```

## Function Design

**Size:**
- Shell functions: Keep to single responsibility (e.g., `print_success()` only outputs status, `docker_build_mp()` only builds images)
- Terraform modules: Organized by concern (controller, worker, prerequisites)
- Makefile targets: One logical operation per target (e.g., `validate` vs `validate/full`)

**Parameters:**
- Shell: Pass positional args (e.g., `print_step $1 $2` where $1 is phase number, $2 is description)
- Terraform: Use `var.*` for inputs and explicitly pass via module blocks
- Makefile: Use environment variables for parameterization (e.g., `REGISTRY`, `TAG`, `PROJECT_ID`)

**Return Values:**
- Shell: Functions return exit codes (0 = success, non-zero = failure); use stdout for output
- Terraform: Return via `output` blocks (not implicit returns)
- Makefile: Targets succeed silently (exit 0) or fail with error (exit 1+); messages to stdout

**Required Environment Setup:**
- Scripts expect: `set -euo pipefail` at top; this enforces strict error handling
- Path resolution: Use `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` for script location
- Variable defaults: Use `${VAR:-default_value}` for optional variables

## Module Design

**Exports (Exports in Terraform):**
- Terraform modules export via `output` blocks (see `outputs.tf` files)
- Example: `output "controller_load_balancer_ip" { value = google_compute_address.controller_lb.address }`
- All outputs have descriptions for clarity

**Barrel Files:**
- Not used in this codebase
- Terraform modules are standard directory structures: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
- Common functions sourced explicitly: `source "$SHARED_DIR/scripts/lib/common.sh"`

**File Organization:**
- Each Terraform module is a directory with standard files:
  - `main.tf` - Resource definitions
  - `variables.tf` - Input variables with descriptions and validation
  - `outputs.tf` - Output values
  - `versions.tf` - Provider constraints
  - `templates/` - Cloud-init scripts or other templates (as needed)

**Module Patterns:**
- Local modules referenced via relative paths: `source = "./modules/controller"`
- Remote modules via git: `source = "git::https://github.com/hashicorp/..."`
- All module variables explicitly passed in parent module (see `main.tf` module blocks)

## Parameterization Pattern

**Critical for Marketplace:**
- NEVER hardcode: `PROJECT_ID`, `REGISTRY`, `CLUSTER_NAME`, `ZONE`, `APP_ID`
- Use environment variables: `REGISTRY=us-docker.pkg.dev/$PROJECT_ID/repo TAG=1.21.0 make release`
- Makefile defaults: `$(or $(REGISTRY),default-value)` pattern allows override
- Terraform variables: All inputs parameterized (no hardcoded resource names)
- Scripts: Parse arguments and environment variables (see `validate-marketplace.sh` argument parsing)

**GCP Marketplace Requirements:**
- `MP_SERVICE_NAME` must be passed to all image builds (annotation requirement)
- `REGISTRY` must support both GCR (`gcr.io/project/path`) and Artifact Registry (`us-docker.pkg.dev/project/repo`)
- Version tags: Major and minor versions required (e.g., `1.21.0` tagged as `1.21` and `1`)

## Linting & Pre-commit

**Current Status:**
- No `.pre-commit-config.yaml` at repository root
- Some products (e.g., terraform modules in `.terraform/modules/`) may have pre-commit configs (from upstream)
- Validation done manually via `make` targets

**Validation Workflow:**
- Shell syntax: Implicit via `bash -n` or execution with `set -euo pipefail`
- Terraform: `terraform validate` as part of `make terraform/validate`
- CFT: `cft blueprint metadata -p . -v` for GCP Marketplace metadata
- Schema: mpdev schema validation in `validate-marketplace.sh`

## Version & Dependency Management

**Terraform:**
- Providers locked in `versions.tf` with version constraints: `required_version = ">= 1.0"`
- Common providers: `google`, `google-beta`, `random`, `time`, `tls`, `null`
- No external modules sourced from registries (only local and git repos)

**Shell:**
- No dependencies beyond standard UNIX tools and gcloud SDK
- Tools checked at runtime: `command -v docker &>/dev/null` pattern
- Docker images specified in `Dockerfile` with exact versions (e.g., `FROM ubuntu:22.04`)

**Makefiles:**
- Shared infrastructure: `shared/Makefile.common`, `shared/Makefile.product`
- Each product can override via product-specific targets
- Version extracted from: `grep 'ARG VERSION=' images/*/Dockerfile | cut -d= -f2`

---

*Convention analysis: 2025-02-24*
