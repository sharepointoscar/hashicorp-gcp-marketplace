# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Required
#------------------------------------------------------------------------------
variable "project_id" {
  type        = string
  description = "GCP project ID to deploy Nomad Enterprise into."
}

variable "region" {
  type        = string
  description = "GCP region for all resources."
  default     = "us-central1"
}

variable "nomad_fqdn" {
  type        = string
  description = "Fully qualified domain name for Nomad cluster (used for TLS and peer joining)."
}

variable "license_file_path" {
  type        = string
  description = "Path to the Nomad Enterprise license file (.hclic)."
}

#------------------------------------------------------------------------------
# TLS Configuration
#------------------------------------------------------------------------------
variable "tls_cert_path" {
  type        = string
  description = "Path to TLS certificate file. If null, a self-signed certificate is generated."
  default     = null
}

variable "tls_key_path" {
  type        = string
  description = "Path to TLS private key file. If null, a self-signed key is generated."
  default     = null
}

variable "tls_ca_bundle_path" {
  type        = string
  description = "Path to CA bundle file. Optional, for custom CA chains."
  default     = null
}

#------------------------------------------------------------------------------
# Network
#------------------------------------------------------------------------------
variable "vpc_name" {
  type        = string
  description = "Name of the VPC network."
  default     = "default"
}

variable "subnet_name" {
  type        = string
  description = "Name of the subnet within the VPC."
  default     = "default"
}

variable "vpc_project_id" {
  type        = string
  description = "Project ID containing the VPC (for Shared VPC). Defaults to project_id if null."
  default     = null
}

#------------------------------------------------------------------------------
# Nomad Configuration
#------------------------------------------------------------------------------
variable "nomad_version" {
  type        = string
  description = "Version of Nomad Enterprise to install."
  default     = "1.11.2+ent"
}

variable "nomad_datacenter" {
  type        = string
  description = "Nomad datacenter name for the server cluster."
  default     = "dc1"
}

variable "nomad_region" {
  type        = string
  description = "Nomad region name. Defaults to null (uses Nomad default)."
  default     = null
}

variable "node_count" {
  type        = number
  description = "Number of Nomad server nodes (must be odd: 1, 3, 5)."
  default     = 3
}

variable "nomad_acl_enabled" {
  type        = bool
  description = "Enable Nomad ACLs."
  default     = true
}

variable "nomad_enable_ui" {
  type        = bool
  description = "Enable Nomad web UI."
  default     = true
}

#------------------------------------------------------------------------------
# Compute
#------------------------------------------------------------------------------
variable "machine_type" {
  type        = string
  description = "GCE machine type for Nomad server VMs."
  default     = "n2-standard-4"
}

variable "boot_disk_size" {
  type        = number
  description = "Boot disk size in GB."
  default     = 100
}

variable "data_disk_size" {
  type        = number
  description = "Nomad data disk size in GB (Raft storage)."
  default     = 50
}

variable "audit_disk_size" {
  type        = number
  description = "Nomad audit log disk size in GB."
  default     = 50
}

#------------------------------------------------------------------------------
# DNS
#------------------------------------------------------------------------------
variable "create_cloud_dns_record" {
  type        = bool
  description = "Create a Cloud DNS A record for nomad_fqdn pointing to the load balancer."
  default     = false
}

variable "cloud_dns_managed_zone" {
  type        = string
  description = "Cloud DNS managed zone name (required if create_cloud_dns_record is true)."
  default     = null
}

#------------------------------------------------------------------------------
# Firewall
#------------------------------------------------------------------------------
variable "cidr_ingress_api_allow" {
  type        = list(string)
  description = "CIDR ranges allowed to access the Nomad API (port 4646)."
  default     = ["0.0.0.0/0"]
}

variable "cidr_ingress_rpc_allow" {
  type        = list(string)
  description = "CIDR ranges allowed for RPC/Serf traffic (ports 4647, 4648)."
  default     = ["0.0.0.0/0"]
}

#------------------------------------------------------------------------------
# Load Balancer
#------------------------------------------------------------------------------
variable "load_balancing_scheme" {
  type        = string
  description = "Type of load balancer: INTERNAL, EXTERNAL, or NONE."
  default     = "INTERNAL"

  validation {
    condition     = contains(["INTERNAL", "EXTERNAL", "NONE"], var.load_balancing_scheme)
    error_message = "Must be INTERNAL, EXTERNAL, or NONE."
  }
}

#------------------------------------------------------------------------------
# GCS Snapshots
#------------------------------------------------------------------------------
variable "create_snapshot_bucket" {
  type        = bool
  description = "Create a GCS bucket for Nomad Raft snapshots."
  default     = true
}

#------------------------------------------------------------------------------
# Labels
#------------------------------------------------------------------------------
variable "common_labels" {
  type        = map(string)
  description = "Common labels to apply to all GCP resources."
  default     = {}
}

#------------------------------------------------------------------------------
# GCP Marketplace
#------------------------------------------------------------------------------
variable "goog_cm_deployment_name" {
  type        = string
  description = "Marketplace deployment name (auto-populated by GCP Marketplace UI)."
  default     = ""
}

variable "friendly_name_prefix" {
  type        = string
  description = "Prefix for resource names when not deployed via Marketplace."
  default     = "nomad"
}

variable "nomad_image" {
  type        = string
  description = "Packer-built VM image for Nomad (overrides default Ubuntu image)."
  default     = "projects/ibm-software-mp-project/global/images/hashicorp-ubuntu2204-nomad-x86-64-v1112-20260226"
}
