# Boundary Enterprise GCP Marketplace Test Configuration
# Generated for testing in project: ibm-software-mp-project-test

#------------------------------------------------------------------------------
# Required Configuration
#------------------------------------------------------------------------------

project_id = "ibm-software-mp-project-test"
region     = "us-central1"

# FQDN - will point to LB IP after deployment
boundary_fqdn = "boundary.example.com"

# Secret Manager secrets (created automatically)
boundary_license_secret_id           = "boundary-license"
boundary_tls_cert_secret_id          = "boundary-tls-cert"
boundary_tls_privkey_secret_id       = "boundary-tls-key"
boundary_database_password_secret_id = "boundary-db-password"

#------------------------------------------------------------------------------
# Network Configuration
#------------------------------------------------------------------------------

vpc_name               = "default"
controller_subnet_name = "default"

#------------------------------------------------------------------------------
# Minimal Test Configuration (reduce costs)
#------------------------------------------------------------------------------

controller_instance_count     = 1
ingress_worker_instance_count = 1
egress_worker_instance_count  = 1
deploy_ingress_worker         = true
deploy_egress_worker          = false

#------------------------------------------------------------------------------
# Marketplace
#------------------------------------------------------------------------------

goog_cm_deployment_name = "mp-test"
