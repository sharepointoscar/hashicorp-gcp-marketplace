# test.tfvars - Real values for local testing before Partner Portal
# Run: terraform apply -var-file=test.tfvars

# Project
project_id = "ibm-software-mp-project-test"
region     = "us-central1"

# Existing GKE Cluster
cluster_name     = "vault-mp-test"
cluster_location = "us-central1-a"

# Networking (use existing VPC)
network_name    = "default"
subnetwork_name = "default"

# TFE Deployment
namespace     = "terraform-enterprise"
replica_count = 1
tfe_hostname  = "tfe.example.com"

# Infrastructure sizing (smaller for testing)
database_tier    = "db-custom-2-8192"
database_version = "POSTGRES_16"
gcs_location     = "US"

# Private Service Access already exists in this VPC
create_private_service_access = false

# Images from Artifact Registry (just built)
tfe_image_repo      = "us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace/tfe"
tfe_image_tag       = "1.1.3"
ubbagent_image_repo = "us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace/ubbagent"
ubbagent_image_tag  = "1.1.3"

# Helm chart from Artifact Registry
helm_chart_repo    = "oci://us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace"
helm_chart_name    = "terraform-enterprise-chart"
helm_chart_version = "1.1.3"

# =============================================================================
# SENSITIVE VALUES - Set via environment variables or replace placeholders
# =============================================================================

# TFE License (from file)
# tfe_license = "contents of terraform exp Mar 31 2026.hclic"

# Encryption password (min 16 chars)
# tfe_encryption_password = "your-encryption-password-here"

# TLS Certificates (base64-encoded)
# Generate with: cat cert.pem | base64 -w0
# tls_certificate = "base64-encoded-cert"
# tls_private_key = "base64-encoded-key"
# ca_certificate  = "base64-encoded-ca"
