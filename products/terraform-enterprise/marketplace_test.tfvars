# marketplace_test.tfvars - Test values for GCP Marketplace validation
# These values are used by GCP Marketplace when running `terraform plan` validation
#
# DO NOT include in this file:
# - project_id (provided by GCP Marketplace)
# - Variables declared in schema.yaml (tfe_image_repo, tfe_image_tag, etc.)
# - helm_chart_repo, helm_chart_name, helm_chart_version (set by Marketplace)

# GKE Cluster (must exist for validation)
cluster_name     = "vault-mp-test"
cluster_location = "us-central1"

# Deployment configuration
namespace     = "terraform-enterprise"
replica_count = 1

# TFE Configuration
tfe_hostname = "tfe.example.com"

# Networking
network_name    = "default"
subnetwork_name = "default"
region          = "us-central1"

# Infrastructure sizing
database_tier    = "db-custom-2-8192"
database_version = "POSTGRES_16"
gcs_location     = "US"

# Sensitive values (placeholders for validation - actual values from customer)
tfe_license             = "placeholder-license-for-validation"
tfe_encryption_password = "placeholder-encryption-password"

# TLS certificates (base64-encoded placeholders)
tls_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCnBsYWNlaG9sZGVyCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K"
tls_private_key = "LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCnBsYWNlaG9sZGVyCi0tLS0tRU5EIFBSSVZBVEUgS0VZLS0tLS0K"
ca_certificate  = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCnBsYWNlaG9sZGVyCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K"
