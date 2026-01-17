# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# HashiCorp Boundary Enterprise - GCP Marketplace Deployment
#
# This module orchestrates the deployment of Boundary Enterprise on GCP using
# HashiCorp Validated Design (HVD) patterns:
# - Controllers: Boundary control plane on Compute Engine
# - Workers: Ingress and egress workers for session proxying
# - Cloud SQL: PostgreSQL database backend
# - Cloud KMS: Encryption key management
# - GCS: Session recording storage (optional)
#------------------------------------------------------------------------------

locals {
  # Use Marketplace deployment name if provided, otherwise use friendly_name_prefix
  name_prefix = var.goog_cm_deployment_name != "" ? var.goog_cm_deployment_name : var.friendly_name_prefix

  # Worker subnet defaults to controller subnet if not specified
  worker_subnet = var.worker_subnet_name != null ? var.worker_subnet_name : var.controller_subnet_name

  # Common labels for all resources
  labels = merge(var.common_labels, {
    gcp-marketplace = "boundary-enterprise"
  })
}

#------------------------------------------------------------------------------
# Boundary Controller Cluster
#------------------------------------------------------------------------------

module "controller" {
  source = "./modules/controller"

  # Project and region
  project_id           = var.project_id
  region               = var.region
  friendly_name_prefix = local.name_prefix

  # Boundary configuration
  boundary_fqdn                  = var.boundary_fqdn
  boundary_version               = var.boundary_version
  boundary_license_secret_id     = var.boundary_license_secret_id
  boundary_tls_cert_secret_id    = var.boundary_tls_cert_secret_id
  boundary_tls_privkey_secret_id = var.boundary_tls_privkey_secret_id
  boundary_tls_ca_bundle_secret_id = var.boundary_tls_ca_bundle_secret_id
  enable_session_recording       = var.enable_session_recording

  # Network
  vpc                       = var.vpc_name
  vpc_project_id            = var.vpc_project_id
  subnet_name               = var.controller_subnet_name
  api_load_balancing_scheme = var.api_load_balancing_scheme

  # DNS
  create_cloud_dns_record = var.create_cloud_dns_record
  cloud_dns_managed_zone  = var.cloud_dns_managed_zone

  # Firewall
  cidr_ingress_ssh_allow  = var.cidr_ingress_ssh_allow
  cidr_ingress_9200_allow = var.cidr_ingress_api_allow
  cidr_ingress_9201_allow = var.cidr_ingress_worker_allow

  # Compute
  instance_count = var.controller_instance_count
  machine_type   = var.controller_machine_type
  disk_size_gb   = var.controller_disk_size_gb

  # Database
  postgres_version           = var.postgres_version
  postgres_machine_type      = var.postgres_machine_type
  postgres_disk_size         = var.postgres_disk_size
  postgres_availability_type = var.postgres_availability_type

  # Labels
  common_labels = local.labels
}

#------------------------------------------------------------------------------
# Ingress Worker (Public-facing)
#------------------------------------------------------------------------------

module "ingress_worker" {
  source = "./modules/worker"
  count  = var.deploy_ingress_worker ? 1 : 0

  # Project and region
  project_id           = var.project_id
  region               = var.region
  friendly_name_prefix = "${local.name_prefix}-ing"

  # Boundary configuration
  boundary_version           = var.boundary_version
  boundary_upstream          = [var.boundary_fqdn]
  boundary_upstream_port     = 9201
  worker_is_internal         = false  # Public IP for ingress
  enable_session_recording   = var.enable_session_recording

  # Network
  vpc         = var.vpc_name
  vpc_project_id = var.vpc_project_id
  subnet_name = local.worker_subnet
  create_lb   = true  # Load balancer for downstream workers/clients

  # Firewall
  cidr_ingress_ssh_allow  = var.cidr_ingress_ssh_allow
  cidr_ingress_9202_allow = var.cidr_ingress_worker_allow

  # KMS - use controller's key ring
  key_ring_location = var.region
  key_ring_name     = module.controller.created_boundary_keyring_name
  key_name          = module.controller.created_boundary_worker_key_name

  # Compute
  instance_count = var.ingress_worker_instance_count
  machine_type   = var.worker_machine_type
  disk_size_gb   = var.worker_disk_size_gb

  # Labels
  common_labels = local.labels
  worker_tags = {
    worker-type = "ingress"
  }

  depends_on = [module.controller]
}

#------------------------------------------------------------------------------
# Egress Worker (Private)
#------------------------------------------------------------------------------

module "egress_worker" {
  source = "./modules/worker"
  count  = var.deploy_egress_worker ? 1 : 0

  # Project and region
  project_id           = var.project_id
  region               = var.region
  friendly_name_prefix = "${local.name_prefix}-egr"

  # Boundary configuration
  boundary_version           = var.boundary_version
  boundary_upstream          = var.deploy_ingress_worker ? [module.ingress_worker[0].worker_lb_ip] : [var.boundary_fqdn]
  boundary_upstream_port     = var.deploy_ingress_worker ? 9202 : 9201
  worker_is_internal         = true  # No public IP for egress
  enable_session_recording   = var.enable_session_recording

  # Network
  vpc         = var.vpc_name
  vpc_project_id = var.vpc_project_id
  subnet_name = local.worker_subnet
  create_lb   = false  # No load balancer needed

  # Firewall
  cidr_ingress_ssh_allow  = var.cidr_ingress_ssh_allow
  cidr_ingress_9202_allow = null  # No external access needed

  # KMS - use controller's key ring
  key_ring_location = var.region
  key_ring_name     = module.controller.created_boundary_keyring_name
  key_name          = module.controller.created_boundary_worker_key_name

  # Compute
  instance_count = var.egress_worker_instance_count
  machine_type   = var.worker_machine_type
  disk_size_gb   = var.worker_disk_size_gb

  # Labels
  common_labels = local.labels
  worker_tags = {
    worker-type = "egress"
  }

  depends_on = [module.controller, module.ingress_worker]
}
