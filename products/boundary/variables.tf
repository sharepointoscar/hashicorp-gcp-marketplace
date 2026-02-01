# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

variable "project_id" {
  type        = string
  description = "GCP project ID to deploy Boundary Enterprise into."
}

variable "region" {
  type        = string
  description = "GCP region to deploy Boundary Enterprise into."
}

variable "friendly_name_prefix" {
  type        = string
  description = "Friendly name prefix for uniquely naming resources (max 12 chars, no 'boundary')."
  default     = "mp"

  validation {
    condition     = !strcontains(var.friendly_name_prefix, "boundary")
    error_message = "Value must not contain 'boundary' to avoid redundancy."
  }

  validation {
    condition     = length(var.friendly_name_prefix) < 13
    error_message = "Value must be less than 13 characters."
  }
}

variable "boundary_fqdn" {
  type        = string
  description = "Fully qualified domain name for Boundary. Must resolve to the load balancer IP."
}

variable "boundary_license_secret_id" {
  type        = string
  description = "Secret Manager secret ID containing the Boundary Enterprise license."
}

variable "boundary_tls_cert_secret_id" {
  type        = string
  description = "Secret Manager secret ID containing the TLS certificate (base64-encoded PEM)."
}

variable "boundary_tls_privkey_secret_id" {
  type        = string
  description = "Secret Manager secret ID containing the TLS private key (base64-encoded PEM)."
}

variable "boundary_database_password_secret_id" {
  type        = string
  description = "Secret Manager secret ID containing the PostgreSQL database password."
}

#------------------------------------------------------------------------------
# Network Configuration
#------------------------------------------------------------------------------

variable "vpc_name" {
  type        = string
  description = "Name of existing VPC network for Boundary deployment."
}

variable "controller_subnet_name" {
  type        = string
  description = "Name of existing subnet for Boundary controllers."
}

variable "worker_subnet_name" {
  type        = string
  description = "Name of existing subnet for Boundary workers. Can be same as controller subnet."
  default     = null
}

variable "vpc_project_id" {
  type        = string
  description = "Project ID where the VPC resides (if different from deployment project)."
  default     = null
}

variable "create_proxy_subnet" {
  type        = bool
  description = "Create a proxy-only subnet for the internal load balancer. Required if one doesn't exist in the VPC/region."
  default     = true
}

variable "proxy_subnet_cidr" {
  type        = string
  description = "CIDR range for the proxy-only subnet. Must not overlap with existing subnets."
  default     = "192.168.100.0/23"
}

#------------------------------------------------------------------------------
# Boundary Configuration
#------------------------------------------------------------------------------

variable "boundary_version" {
  type        = string
  description = "Boundary Enterprise version to install."
  default     = "0.21.0+ent"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\+ent$", var.boundary_version))
    error_message = "Value must be in format 'X.Y.Z+ent'."
  }
}

variable "enable_session_recording" {
  type        = bool
  description = "Enable Boundary Session Recording (BSR)."
  default     = false
}

variable "boundary_tls_ca_bundle_secret_id" {
  type        = string
  description = "Secret Manager secret ID for custom CA bundle (base64-encoded PEM). Optional."
  default     = null
}

#------------------------------------------------------------------------------
# Controller Configuration
#------------------------------------------------------------------------------

variable "controller_instance_count" {
  type        = number
  description = "Number of Boundary controller instances."
  default     = 3
}

variable "controller_machine_type" {
  type        = string
  description = "Machine type for controller instances."
  default     = "n2-standard-4"
}

variable "controller_disk_size_gb" {
  type        = number
  description = "Boot disk size (GB) for controller instances."
  default     = 50
}

variable "api_load_balancing_scheme" {
  type        = string
  description = "Load balancer scheme: 'internal' or 'external'."
  default     = "external"

  validation {
    condition     = contains(["external", "internal"], var.api_load_balancing_scheme)
    error_message = "Must be 'external' or 'internal'."
  }
}

#------------------------------------------------------------------------------
# Worker Configuration
#------------------------------------------------------------------------------

variable "deploy_ingress_worker" {
  type        = bool
  description = "Deploy an ingress worker (public-facing with load balancer)."
  default     = true
}

variable "deploy_egress_worker" {
  type        = bool
  description = "Deploy an egress worker (private, connects to targets)."
  default     = true
}

variable "ingress_worker_instance_count" {
  type        = number
  description = "Number of ingress worker instances."
  default     = 2
}

variable "egress_worker_instance_count" {
  type        = number
  description = "Number of egress worker instances."
  default     = 2
}

variable "worker_machine_type" {
  type        = string
  description = "Machine type for worker instances."
  default     = "n2-standard-2"
}

variable "worker_disk_size_gb" {
  type        = number
  description = "Boot disk size (GB) for worker instances."
  default     = 50
}

#------------------------------------------------------------------------------
# Database Configuration
#------------------------------------------------------------------------------

variable "postgres_version" {
  type        = string
  description = "Cloud SQL PostgreSQL version."
  default     = "POSTGRES_16"
}

variable "postgres_machine_type" {
  type        = string
  description = "Cloud SQL instance tier."
  default     = "db-custom-4-16384"
}

variable "postgres_disk_size" {
  type        = number
  description = "Cloud SQL disk size (GB)."
  default     = 50
}

variable "postgres_availability_type" {
  type        = string
  description = "Cloud SQL availability: 'ZONAL' or 'REGIONAL'."
  default     = "REGIONAL"
}

#------------------------------------------------------------------------------
# DNS Configuration
#------------------------------------------------------------------------------

variable "create_cloud_dns_record" {
  type        = bool
  description = "Create Cloud DNS record for boundary_fqdn."
  default     = false
}

variable "cloud_dns_managed_zone" {
  type        = string
  description = "Cloud DNS managed zone name (required if create_cloud_dns_record is true)."
  default     = null
}

#------------------------------------------------------------------------------
# Firewall Configuration
#------------------------------------------------------------------------------

variable "cidr_ingress_api_allow" {
  type        = list(string)
  description = "CIDR ranges allowed to access Boundary API (port 9200)."
  default     = ["0.0.0.0/0"]
}

variable "cidr_ingress_worker_allow" {
  type        = list(string)
  description = "CIDR ranges allowed to access workers (port 9202)."
  default     = ["0.0.0.0/0"]
}

variable "cidr_ingress_ssh_allow" {
  type        = list(string)
  description = "CIDR ranges allowed for SSH via IAP."
  default     = ["10.0.0.0/8"]
}

#------------------------------------------------------------------------------
# Labels
#------------------------------------------------------------------------------

variable "common_labels" {
  type        = map(string)
  description = "Common labels to apply to all resources."
  default = {
    managed-by = "terraform"
    product    = "boundary-enterprise"
  }
}

#------------------------------------------------------------------------------
# GCP Marketplace
#------------------------------------------------------------------------------

variable "boundary_image_family" {
  type        = string
  description = "Compute Engine image family for Boundary instances."
  default     = "boundary-enterprise"
}

variable "boundary_image_project" {
  type        = string
  description = "GCP project containing the Boundary VM image. Defaults to project_id."
  default     = null
}

variable "goog_cm_deployment_name" {
  type        = string
  description = "GCP Marketplace deployment name (auto-populated by Marketplace)."
  default     = ""
}

variable "zone" {
  type        = string
  description = "GCP zone for zonal resources (auto-populated by Marketplace)."
  default     = ""
}

variable "adminEmailAddress" {
  type        = string
  description = "Admin email address for notifications (auto-populated by Marketplace)."
  default     = ""
}
