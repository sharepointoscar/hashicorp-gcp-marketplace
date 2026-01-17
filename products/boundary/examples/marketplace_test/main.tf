# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Boundary Enterprise - Marketplace Test Configuration
#
# This example deploys Boundary Enterprise with minimal configuration for
# testing GCP Marketplace validation.
#------------------------------------------------------------------------------

module "boundary" {
  source = "../.."

  # Required
  project_id                     = var.project_id
  region                         = var.region
  boundary_fqdn                  = var.boundary_fqdn
  boundary_license_secret_id     = var.boundary_license_secret_id
  boundary_tls_cert_secret_id    = var.boundary_tls_cert_secret_id
  boundary_tls_privkey_secret_id = var.boundary_tls_privkey_secret_id

  # Network
  vpc_name               = var.vpc_name
  controller_subnet_name = var.controller_subnet_name

  # Optional overrides
  boundary_version             = var.boundary_version
  controller_instance_count    = var.controller_instance_count
  ingress_worker_instance_count = var.ingress_worker_instance_count
  egress_worker_instance_count  = var.egress_worker_instance_count
  deploy_ingress_worker        = var.deploy_ingress_worker
  deploy_egress_worker         = var.deploy_egress_worker

  # Marketplace
  goog_cm_deployment_name = var.goog_cm_deployment_name
}
