# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# HashiCorp Nomad Enterprise - GCP Marketplace Deployment
#
# This module orchestrates the deployment of Nomad Enterprise on GCP using
# HashiCorp Validated Design (HVD) patterns:
# - Server VMs: Regional MIG with Raft consensus across 3 availability zones
# - Secret Manager: License, TLS certificates, gossip encryption key
# - GCS: Raft snapshot storage (optional)
# - No external database required (Raft integrated storage)
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Providers
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
# Local Values
#------------------------------------------------------------------------------

locals {
  # Use Marketplace deployment name if provided, otherwise use friendly_name_prefix
  name_prefix = var.goog_cm_deployment_name != "" ? var.goog_cm_deployment_name : var.friendly_name_prefix

  # Common labels for all resources
  labels = merge(var.common_labels, {
    gcp-marketplace = "nomad-enterprise"
  })
}

#------------------------------------------------------------------------------
# Prerequisites - Creates secrets, TLS certs, gossip key, and GCS bucket
#------------------------------------------------------------------------------

module "prerequisites" {
  source = "./modules/prerequisites"

  project_id           = var.project_id
  region               = var.region
  friendly_name_prefix = local.name_prefix
  nomad_fqdn           = var.nomad_fqdn
  nomad_datacenter     = var.nomad_datacenter
  nomad_region         = var.nomad_region != null ? var.nomad_region : "global"
  license_file_path    = var.license_file_path

  tls_cert_path      = var.tls_cert_path
  tls_key_path       = var.tls_key_path
  tls_ca_bundle_path = var.tls_ca_bundle_path

  create_snapshot_bucket = var.create_snapshot_bucket

  labels = local.labels
}

#------------------------------------------------------------------------------
# Nomad Server Cluster
#------------------------------------------------------------------------------

module "server" {
  source = "./modules/server"

  # Project and region
  project_id         = var.project_id
  region             = var.region
  application_prefix = local.name_prefix

  # Nomad configuration
  nomad_fqdn       = var.nomad_fqdn
  nomad_server     = true
  nomad_client     = false
  nomad_datacenter = var.nomad_datacenter
  nomad_region     = var.nomad_region
  nomad_version    = var.nomad_version
  nomad_enable_ui  = var.nomad_enable_ui
  nomad_acl_enabled = var.nomad_acl_enabled

  # Secret Manager references from prerequisites
  nomad_license_sm_secret_name       = module.prerequisites.license_secret_name
  nomad_tls_cert_sm_secret_name      = module.prerequisites.tls_cert_secret_name
  nomad_tls_privkey_sm_secret_name   = module.prerequisites.tls_key_secret_name
  nomad_tls_ca_bundle_sm_secret_name = module.prerequisites.ca_bundle_secret_name
  nomad_gossip_key_secret_name       = module.prerequisites.gossip_key_secret_name

  # GCS snapshot bucket
  nomad_snapshot_gcs_bucket_name = module.prerequisites.snapshot_bucket_name

  # Network
  network            = var.vpc_name
  subnetwork         = var.subnet_name
  network_project_id = var.vpc_project_id

  # DNS
  create_cloud_dns_record = var.create_cloud_dns_record
  cloud_dns_managed_zone  = var.cloud_dns_managed_zone

  # Firewall
  cidr_ingress_api_allow = var.cidr_ingress_api_allow
  cidr_ingress_rpc_allow = var.cidr_ingress_rpc_allow

  # Compute
  node_count          = var.node_count
  machine_type        = var.machine_type
  packer_image        = var.nomad_image
  boot_disk_size      = var.boot_disk_size
  nomad_data_disk_size  = var.data_disk_size
  nomad_audit_disk_size = var.audit_disk_size
  nomad_nodes         = var.node_count

  # Load balancer
  load_balancing_scheme = var.load_balancing_scheme

  # Labels
  common_labels = local.labels

  depends_on = [module.prerequisites]
}
