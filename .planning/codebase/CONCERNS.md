# Codebase Concerns

**Analysis Date:** 2026-02-24

## Tech Debt

**Terraform State Files in Version Control:**
- Issue: Terraform state files (`.tfstate`, `.tfstate.backup`, `.tfstate.d/`) are committed to git
- Files: `products/terraform-enterprise/terraform/terraform.tfstate`, `products/terraform-enterprise/terraform/terraform.tfstate.backup`, `products/terraform-enterprise/terraform/terraform.tfstate.d/*`
- Impact: Exposes infrastructure topology, resource IDs, and potentially sensitive data (database passwords, connection strings). Creates merge conflicts when multiple developers run terraform apply. State files should be remote (Cloud Storage) or gitignored
- Fix approach: Move to `terraform/terraform.tfstate.d/.gitignore` pattern with remote backend in `backend.tf`, or use GCS with Terraform state locking

**Deprecated GCP IAM Roles:**
- Issue: Using `roles/storage.legacyBucketReader` which is deprecated
- Files: `products/boundary/modules/controller/iam.tf:241`
- Impact: Legacy roles lack granularity and may be removed in future GCP API updates
- Fix approach: Replace with `roles/storage.objectViewer` for read-only access, or more specific role bindings

**Legacy Health Check IP Range:**
- Issue: Using `data.google_netblock_ip_ranges.legacy` for GCP health checkers
- Files: `products/nomad/modules/server/data.tf:21-22`, `products/nomad/modules/server/lb.tf:17`
- Impact: Legacy API may be deprecated; should use current GCP health check documentation
- Fix approach: Replace with current health check IP ranges from GCP documentation

**Deprecated PostgreSQL Connection Parameter:**
- Issue: Comment in TFE terraform notes deprecated SSL parameter usage
- Files: `products/terraform-enterprise/terraform/modules/infrastructure/main.tf:78` (comment notes `ssl_mode` instead of `require_ssl`)
- Impact: Documentation inconsistency; may affect future Cloud SQL upgrades
- Fix approach: Audit all PostgreSQL connection strings for consistent parameter naming

**Commented-Out Debug Configuration in TFE Helm Chart:**
- Issue: Debug environment variables commented out but not removed
- Files: `products/terraform-enterprise/chart/terraform-enterprise/values.yaml:319-320`
- Impact: Creates confusion about whether debug mode is supported; can be accidentally enabled
- Fix approach: Either document debug mode as unsupported feature or enable it properly with feature flags

**TODO Comments in Upstream Terraform Modules:**
- Issue: Unresolved TODOs in vendored `terraform-google-project-factory` module
- Files: `products/terraform-enterprise/terraform/.terraform/modules/project_services/modules/core_project_factory/main.tf:118`, `products/terraform-enterprise/terraform/.terraform/modules/project_services/modules/fabric-project/variables.tf:86`
- Impact: Technical debt from external dependencies; unclear if these affect marketplace products
- Fix approach: Document whether these TODOs impact marketplace deployments, or maintain fork with resolved issues

**Missing Vault Icon Asset:**
- Issue: Placeholder comment about missing Vault icon in schema
- Files: `products/vault/manifest/application.yaml.template:10`
- Impact: Vault listing on GCP Marketplace displays generic icon instead of branded asset
- Fix approach: Obtain base64-encoded Vault Enterprise official icon from HashiCorp and replace placeholder

---

## Known Bugs

**MinIO Pod Readiness Issue (Previously Fixed):**
- Symptoms: MinIO pod stuck at 1/2 ready during TFE deployment, blocking TFE startup
- Files: `products/terraform-enterprise/chart/terraform-enterprise/templates/embedded-minio.yaml`, `products/terraform-enterprise/CLAUDE.md:118`
- Cause: Init containers for bucket creation were attached to MinIO sidecar instead of TFE init container
- Workaround: Bucket creation must happen in TFE init containers (`create-minio-bucket` container in deployment.yaml)
- Status: RESOLVED in current version; documented in CLAUDE.md to prevent regression

**Embedded PostgreSQL SSL Configuration:**
- Symptoms: `pq: SSL is not enabled on the server` error during TFE startup
- Files: `products/terraform-enterprise/CLAUDE.md:115`, `products/terraform-enterprise/chart/terraform-enterprise/templates/embedded-postgres.yaml`
- Cause: PostgreSQL init container must generate self-signed SSL certificates before startup
- Status: RESOLVED; init container added in deployment.yaml

**Version Synchronization Mismatches:**
- Symptoms: `Invalid schema publishedVersion` error from mpdev verify
- Files: `products/terraform-enterprise/schema.yaml`, `products/terraform-enterprise/apptest/deployer/schema.yaml`, `products/terraform-enterprise/Makefile`
- Cause: publishedVersion must be full semver (e.g., `1.1.3` not `1.1`); files must match exactly
- Workaround: Always update 4 files in lockstep; use scripts to validate before building
- Mitigation: Document in CLAUDE.md (currently present in TFE)

---

## Security Considerations

**Terraform State Contains Sensitive Data:**
- Risk: `.tfstate` files contain plaintext database passwords, API keys, and encryption keys
- Files: `products/terraform-enterprise/terraform/terraform.tfstate`, `products/terraform-enterprise/terraform/terraform.tfstate.d/production/terraform.tfstate`
- Current mitigation: Files are gitignored in `.gitignore`; should verify .gitignore entries
- Recommendations:
  1. Audit git history for any state file commits (use `git log --diff-filter=D --summary | grep delete`)
  2. Move all state to GCS with encryption and state locking
  3. Add pre-commit hook to prevent `.tfstate` commits
  4. Document in repo that state files are never committed

**Production Configuration in Version Control:**
- Risk: `marketplace_prod.tfvars` contains production variable values that may include FQDN, region, and other deployment hints
- Files: `products/terraform-enterprise/terraform/marketplace_prod.tfvars`
- Current mitigation: File exists but marked read-only (`-r--r--r--`)
- Recommendations:
  1. Review contents for any sensitive defaults
  2. Consider moving to Cloud Storage with IAM controls
  3. Document that production vars are not for CI/CD use

**License File Storage:**
- Risk: `.hclic` files contain enterprise license keys and are gitignored, but if accidentally committed would leak licensing data
- Files: `products/boundary/boundary.hclic`, `products/nomad/nomad exp Mar 31 2026.hclic`, `products/vault/*.hclic`, `products/consul/*.hclic`
- Current mitigation: All entries in `.gitignore`
- Recommendations:
  1. Verify all `.gitignore` patterns cover `*.hclic` and `*.lic`
  2. Use `git hook` to prevent license file commits
  3. Document secure storage procedure in README for each product

**KMS Key Rotation Not Documented:**
- Risk: Boundary uses 4 separate KMS keys (root, worker, recovery, BSR) but rotation procedures are not documented
- Files: `products/boundary/modules/controller/`, `products/boundary/modules/worker/`
- Current mitigation: None; keys are created but rotation is manual/external process
- Recommendations:
  1. Add documented procedure for KMS key rotation in Boundary CLAUDE.md
  2. Implement Cloud KMS automatic rotation in Terraform if supported
  3. Add playbook to Cloud Monitoring for key rotation reminders

**Service Account JSON Keys (Removed but Worth Documenting):**
- Risk: Previously used `google_service_account_key` resources (JSON key files)
- Files: `products/boundary/modules/worker/iam.tf:27` (note: "removed")
- Current mitigation: Changed to use attached SA via metadata server
- Recommendations: Document this change in commit message and CLAUDE.md so teams know not to introduce JSON keys

---

## Performance Bottlenecks

**Large Helm Values File:**
- Problem: TFE Helm values file is 482 lines, includes many commented-out options
- Files: `products/terraform-enterprise/chart/terraform-enterprise/values.yaml`
- Cause: Upstream Helm chart includes all possible TFE configuration options
- Impact: Slow to navigate, easy to miss important settings, harder to audit overrides
- Improvement path:
  1. Extract only used values to override section with comments
  2. Keep reference to upstream chart documentation
  3. Generate values from template to reduce maintenance burden

**Large Terraform Variable Files:**
- Problem: Variable files are 450+ lines (Boundary, Nomad)
- Files: `products/boundary/variables.tf:471`, `products/nomad/modules/server/variables.tf:462`
- Cause: Comprehensive input for marketplace UI customization
- Impact: Difficult to identify required vs. optional variables
- Improvement path:
  1. Group variables with variable grouping comments
  2. Create separate `variables-marketplace.tf` for UI-only vars
  3. Auto-generate documentation with terraform-docs

**Complex Cloud-Init Scripts:**
- Problem: Startup scripts for pre-baked images are 290+ lines with idempotency checks
- Files: `products/boundary/packer/scripts/startup-script.sh:290`, `products/nomad/modules/server/templates/nomad_custom_data.sh.tpl`
- Cause: Must handle both fresh deployments and pre-baked image scenarios
- Impact: Hard to debug, prone to subtle ordering issues, slow VM startup
- Improvement path:
  1. Split into separate init containers for each concern
  2. Add structured logging for debugging
  3. Profile startup time on each release

**Instance Template Updates Require Rolling Replace:**
- Problem: Changing Terraform template doesn't auto-update existing MIG instances
- Files: `products/nomad/modules/server/compute.tf`, `products/boundary/modules/controller/compute.tf`
- Cause: GCP MIGs don't auto-roll on template changes without explicit action
- Impact: Deployments can be inconsistent if terraform apply doesn't trigger rolling update
- Improvement path:
  1. Document manual rolling update step in CLAUDE.md (may already be done)
  2. Add `terraform taint` to force rolling update in deployment docs
  3. Consider `max_surge` strategy for zero-downtime updates

---

## Fragile Areas

**Version Synchronization Across 4 Files (TFE Kubernetes):**
- Files: `products/terraform-enterprise/schema.yaml`, `products/terraform-enterprise/apptest/deployer/schema.yaml`, `products/terraform-enterprise/manifest/application.yaml.template`, `products/terraform-enterprise/Makefile`
- Why fragile: Manual sync required; typos cause `publishedVersion` mismatch errors that only appear during mpdev verify (slow feedback)
- Safe modification:
  1. Create script to validate all 4 versions match
  2. Run validation in pre-commit hook
  3. Use bash script to bulk-update all files
- Test coverage: Gaps in pre-commit validation

**Pre-Baked Image Idempotency (Boundary, Nomad):**
- Files: `products/boundary/packer/scripts/startup-script.sh`, `products/nomad/modules/server/templates/nomad_custom_data.sh.tpl`
- Why fragile: Cloud-init must skip installation steps if software already exists; errors cause cascade failures on rolling updates
- Safe modification:
  1. Add explicit checks for each installation step
  2. Log all skipped steps to `/var/log/cloud-init-output.log`
  3. Test with rolling update command after terraform changes
- Test coverage: Limited; only tested on fresh deployments, not rolling updates

**Embedded Services Dependencies (TFE):**
- Files: `products/terraform-enterprise/chart/terraform-enterprise/templates/deployment.yaml` (init containers), `products/terraform-enterprise/chart/terraform-enterprise/templates/embedded-*.yaml`
- Why fragile: TFE init containers must wait for PostgreSQL, Redis, MinIO in correct order; failure in any init container blocks TFE startup with unclear error messages
- Safe modification:
  1. Use explicit `depends-on` probes with timeout
  2. Add detailed logging in each `wait-for-*` init container
  3. Document expected init container sequence in CLAUDE.md (already present)
- Test coverage: Only tested by mpdev verify; no unit tests

**KMS Key References (Boundary):**
- Files: `products/boundary/modules/controller/`, `products/boundary/modules/worker/`
- Why fragile: 4 separate KMS keys (root, worker, recovery, BSR) created and managed; if any key is deleted or rotated without updating Terraform, Boundary fails to start
- Safe modification:
  1. Document KMS key lifecycle in Boundary CLAUDE.md
  2. Add monitoring for key access patterns
  3. Implement key rotation automation
- Test coverage: Not documented; only verified by manual deployment test

**Cloud SQL Password Rotation (Boundary, Terraform Enterprise):**
- Files: `products/boundary/modules/prerequisites/`, `products/terraform-enterprise/terraform/modules/infrastructure/`
- Why fragile: Initial password generated once; if changed outside Terraform, apps lose connection
- Safe modification:
  1. Use Secret Manager for password storage
  2. Document manual rotation procedure
  3. Add health checks to verify database connectivity
- Test coverage: No automated tests for password rotation

---

## Scaling Limits

**Boundary Controller Cloud SQL:**
- Current capacity: Single Cloud SQL instance (not replicated in test setup)
- Limit: Cloud SQL instance reaches CPU/memory limits under load; no automatic failover
- Scaling path:
  1. Enable Cloud SQL High Availability for production
  2. Add read replicas for cross-region failover
  3. Monitor CPU/memory and scale instance class as needed

**TFE Embedded Storage Limitations:**
- Current capacity: Embedded PostgreSQL (single pod), Redis (single pod), MinIO (single pod)
- Limit: No persistence across pod restarts; all data lost if PVC is deleted; single point of failure
- Scaling path:
  1. Add PVC retention policies to prevent accidental data loss
  2. Implement backup strategy (velero or Cloud SQL migration)
  3. Document manual upgrade path to external PostgreSQL/Redis/GCS

**Nomad Server Node Count:**
- Current capacity: Default 3 nodes (minimum for HA)
- Limit: Fixed count; no auto-scaling based on workload
- Scaling path:
  1. Document manual node scaling via Terraform variable
  2. Consider GKE-style auto-scaling using Compute Engine target groups
  3. Implement monitoring for cluster size recommendations

**Boundary Worker Scaling:**
- Current capacity: Manual MIG sizing for ingress/egress workers
- Limit: No auto-scaling; must manually adjust MIG size
- Scaling path:
  1. Add auto-scaling policy based on connection count
  2. Implement load-based health checks for worker selection
  3. Document capacity planning guide

---

## Dependencies at Risk

**Vendored Marketplace Tools (`vendor/marketplace-tools/`):**
- Risk: Google's marketplace-tools is vendored; updates require manual merge
- Impact: Security patches, bug fixes from upstream are not auto-applied
- Migration plan:
  1. Evaluate if newer marketplace-tools supports current Kubernetes versions (1.33+)
  2. Document upgrade path for each product
  3. Consider using git submodule if active development continues

**Forked HVD Modules (Boundary, Nomad):**
- Risk: `modules/controller/`, `modules/worker/`, `modules/server/` are forked from HashiCorp HVD; upstream changes not tracked
- Impact: Security patches, new features in HVD are not auto-merged; version divergence grows
- Migration plan:
  1. Evaluate if upstream HVD supports Terraform marketplace requirements
  2. If not, document divergence from upstream in CLAUDE.md
  3. Create merge strategy for critical security patches
  4. Consider contributing marketplace-specific changes back to HVD

**Terraform Google Provider Compatibility:**
- Risk: Terraform code uses `google` and `google-beta` providers; GCP API deprecations may break builds
- Impact: Provider version bumps require testing all products
- Mitigation: Document provider version constraints in `versions.tf`; test monthly

**GCP Marketplace Verification Tool (mpdev):**
- Risk: `mpdev` is a Google-provided tool; no control over breaking changes
- Impact: Updates to mpdev may break validation for existing products
- Mitigation: Pin mpdev version in validation scripts; test with new versions before adopting

---

## Missing Critical Features

**Automated Backup/Recovery for Embedded Services (TFE):**
- Problem: Embedded PostgreSQL, Redis, MinIO are not backed up
- Blocks: Enterprise deployments requiring disaster recovery
- Solution:
  1. Add Velero integration for pod data snapshots
  2. Implement Cloud SQL migration path for persistent storage
  3. Document manual backup procedures

**Kubernetes Version Compatibility Matrix:**
- Problem: No documented compatibility for GKE versions (Google tests 1.33 + 1.35)
- Blocks: Customers can't determine if their cluster is supported
- Solution:
  1. Add `spec.clusterConstraints` to schema.yaml for each product
  2. Test on GKE 1.33 and 1.35 in CI/CD
  3. Document minimum/maximum supported versions in README

**Automated Testing for Image Annotations:**
- Problem: MP_SERVICE_NAME annotation is critical but not automatically validated
- Blocks: Easy to deploy with missing/wrong annotation, causing GCP Marketplace verification failures
- Solution:
  1. Add `docker manifest inspect` validation to build script
  2. Verify annotation matches MP_SERVICE_NAME environment variable
  3. Fail build if annotation is missing

**Health Check Monitoring Dashboards:**
- Problem: Products have health check endpoints but no monitoring configured
- Blocks: Early detection of degradation (e.g., Boundary database connectivity loss)
- Solution:
  1. Add Cloud Monitoring dashboard templates
  2. Define alerting policies for common failure modes
  3. Document runbooks for alert remediation

**Cross-Product Integration Testing:**
- Problem: Each product is tested in isolation; no tests for multi-product deployments
- Blocks: Unknown compatibility between product versions
- Solution:
  1. Create integration test suite for common topologies
  2. Document tested product version combinations
  3. Add version compatibility matrix to README

---

## Test Coverage Gaps

**Startup Verification (Cloud-Init Idempotency):**
- Untested: Cloud-init script idempotency on rolling updates
- Files: `products/boundary/packer/scripts/startup-script.sh`, `products/nomad/modules/server/templates/nomad_custom_data.sh.tpl`
- Risk: Rolling updates may fail with subtle state-related issues undetected until production
- Priority: High
- Testing approach:
  1. Deploy with Packer image
  2. Trigger MIG rolling update via `gcloud compute instance-groups managed rolling-action replace`
  3. Verify all init containers complete successfully
  4. Run health checks on updated instances

**Database Failover (Boundary Cloud SQL):**
- Untested: Cloud SQL failover behavior in HA configuration
- Files: `products/boundary/modules/controller/`
- Risk: HA failover may drop connections or cause data corruption
- Priority: High
- Testing approach:
  1. Deploy with Cloud SQL HA enabled
  2. Force failover via GCP console
  3. Verify Boundary controllers reconnect within SLA
  4. Validate no data loss or corruption

**KMS Key Rotation (Boundary):**
- Untested: Behavior when KMS keys are rotated
- Files: `products/boundary/modules/controller/`, `products/boundary/modules/worker/`
- Risk: Key rotation may lock Boundary operators out of encrypted data
- Priority: Medium
- Testing approach:
  1. Deploy with KMS integration
  2. Perform manual key rotation in Cloud KMS
  3. Verify Boundary continues to function
  4. Document any manual steps required

**MinIO Persistence (TFE):**
- Untested: MinIO data persistence across pod restarts
- Files: `products/terraform-enterprise/chart/terraform-enterprise/templates/embedded-minio.yaml`
- Risk: Pod restart loses all TFE run artifacts and state storage
- Priority: High
- Testing approach:
  1. Deploy TFE with Minio
  2. Run a Terraform configuration through TFE
  3. Delete MinIO pod
  4. Verify data is recovered (or clearly fails with actionable error)

**TLS Certificate Expiration:**
- Untested: Behavior when TLS certificates expire
- Files: `products/terraform-enterprise/CLAUDE.md:120-124` (TLS handling documented but not tested)
- Risk: Applications become unreachable if certificates expire silently
- Priority: Medium
- Testing approach:
  1. Deploy with test certificates
  2. Advance system clock to certificate expiration date
  3. Verify application behavior and alerting
  4. Document manual renewal procedure

**License Expiration Handling:**
- Untested: Behavior when enterprise licenses expire
- Files: All products using `.hclic` files
- Risk: Unknown degradation mode; products may fail in unexpected ways
- Priority: Low (determined by HashiCorp release cycles)
- Testing approach:
  1. Deploy with test license near expiration
  2. Document expected behavior (graceful warning vs. hard failure)
  3. Add monitoring for license expiration dates

---

## Documentation and Guidance Gaps

**Missing CLAUDE.md for terraform-cloud-agent:**
- Issue: `terraform-cloud-agent` product lacks CLAUDE.md with build/validation guidance
- Files: `products/terraform-cloud-agent/` (directory exists but no CLAUDE.md)
- Impact: Developers must infer build process from Makefile and schema.yaml; no documented gotchas or troubleshooting
- Fix: Create CLAUDE.md following TFE/Vault template structure

**Incomplete Nomad CLAUDE.md Startup Script Section:**
- Issue: Section titled "Cloud-Init Template Design Principles" has incomplete code block
- Files: `products/nomad/CLAUDE.md:145-150`
- Impact: Copy-pasted code snippet is truncated; developers can't see full pattern
- Fix: Complete the code block showing full idempotency check pattern

**Missing Integration Test Documentation:**
- Issue: No documented procedure for testing multiple products together
- Impact: Version compatibility between products is untested; may have hidden breaking changes
- Fix: Add integration testing section to root CLAUDE.md

---

*Concerns audit: 2026-02-24*
