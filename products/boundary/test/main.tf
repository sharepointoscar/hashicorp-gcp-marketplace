# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Boundary Enterprise - Test Deployment
#
# This deploys Boundary Enterprise with all prerequisites automated:
# - Secret Manager secrets (license, TLS, database password)
# - Self-signed TLS certificates (or bring your own)
# - Full Boundary deployment (controllers + workers)
#------------------------------------------------------------------------------

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

#------------------------------------------------------------------------------
# Prerequisites - Creates all required secrets
#------------------------------------------------------------------------------
module "prerequisites" {
  source = "../modules/prerequisites"

  project_id           = var.project_id
  friendly_name_prefix = var.friendly_name_prefix
  boundary_fqdn        = var.boundary_fqdn
  license_file_path    = var.license_file_path

  # Optional: provide your own TLS certs, otherwise self-signed are generated
  tls_cert_path      = var.tls_cert_path
  tls_key_path       = var.tls_key_path
  tls_ca_bundle_path = var.tls_ca_bundle_path

  labels = {
    environment = "test"
    product     = "boundary-enterprise"
  }
}

#------------------------------------------------------------------------------
# Boundary Enterprise Deployment
#------------------------------------------------------------------------------
module "boundary" {
  source = "./.."

  # Required
  project_id    = var.project_id
  region        = var.region
  boundary_fqdn = var.boundary_fqdn

  # Secrets from prerequisites module
  boundary_license_secret_id           = module.prerequisites.license_secret_id
  boundary_tls_cert_secret_id          = module.prerequisites.tls_cert_secret_id
  boundary_tls_privkey_secret_id       = module.prerequisites.tls_key_secret_id
  boundary_database_password_secret_id = module.prerequisites.db_password_secret_id
  boundary_tls_ca_bundle_secret_id     = module.prerequisites.ca_bundle_secret_id

  # Network
  vpc_name               = var.vpc_name
  controller_subnet_name = var.controller_subnet_name

  # Boundary version
  boundary_version = var.boundary_version

  # Controller configuration
  controller_instance_count = var.controller_instance_count
  controller_machine_type   = var.controller_machine_type

  # Worker configuration
  deploy_ingress_worker         = var.deploy_ingress_worker
  deploy_egress_worker          = var.deploy_egress_worker
  ingress_worker_instance_count = var.ingress_worker_instance_count
  egress_worker_instance_count  = var.egress_worker_instance_count

  # Marketplace
  friendly_name_prefix    = var.friendly_name_prefix
  goog_cm_deployment_name = var.goog_cm_deployment_name

  depends_on = [module.prerequisites]
}
