# marketplace_test.tfvars
# Test values for GCP Marketplace Producer Portal validation
# This file provides values for required variables without defaults

# Required - GCP Marketplace deployment identifier
# Note: Must be alphanumeric only and < 13 chars for friendly_name_prefix validation
goog_cm_deployment_name = "mptest"

# Required - Project and Region
region = "us-central1"
zone   = "us-central1-f"

# Required - Admin email for notifications
adminEmailAddress = "default-user@example.com"

# Required - Boundary Configuration
boundary_fqdn = "boundary.example.com"

# Required - Secret Manager IDs (must exist in target project)
# These are placeholder values - actual secrets must be created before deployment
boundary_license_secret_id           = "boundary-license"
boundary_tls_cert_secret_id          = "boundary-tls-cert"
boundary_tls_privkey_secret_id       = "boundary-tls-key"
boundary_database_password_secret_id = "boundary-db-password"

# Required - Network Configuration
vpc_name               = "default"
controller_subnet_name = "default"

# Proxy subnet for internal load balancer
# Set to false if proxy-only subnet already exists in VPC/region
create_proxy_subnet = false

# API load balancer scheme (internal recommended for security)
api_load_balancing_scheme = "internal"
