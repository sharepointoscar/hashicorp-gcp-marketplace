# marketplace_test.tfvars
# Test values for GCP Marketplace Producer Portal validation
# This file provides values for required variables without defaults

# Required - Project and Region
region = "us-central1"

# Required - Boundary Configuration
boundary_fqdn = "boundary.example.com"

# Required - Secret Manager IDs (must exist in target project)
# These are placeholder values - actual secrets must be created before deployment
boundary_license_secret_id          = "boundary-license"
boundary_tls_cert_secret_id         = "boundary-tls-cert"
boundary_tls_privkey_secret_id      = "boundary-tls-key"
boundary_database_password_secret_id = "boundary-db-password"

# Required - Network Configuration
vpc_name               = "default"
controller_subnet_name = "default"

# Org policy compatibility
create_service_account_keys = false
create_cloud_nat            = false
create_proxy_subnet         = false
