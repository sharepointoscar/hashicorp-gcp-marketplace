# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GCP region."
  default     = "us-central1"
}

variable "boundary_fqdn" {
  type        = string
  description = "FQDN for Boundary."
}

variable "license_file_path" {
  type        = string
  description = "Path to Boundary Enterprise license file (.hclic)."
}

#------------------------------------------------------------------------------
# TLS Configuration (optional - self-signed if not provided)
#------------------------------------------------------------------------------

variable "tls_cert_path" {
  type        = string
  description = "Path to TLS certificate file. If null, self-signed cert is generated."
  default     = null
}

variable "tls_key_path" {
  type        = string
  description = "Path to TLS private key file. If null, self-signed key is generated."
  default     = null
}

variable "tls_ca_bundle_path" {
  type        = string
  description = "Path to CA bundle file. Optional."
  default     = null
}

#------------------------------------------------------------------------------
# Network Variables
#------------------------------------------------------------------------------

variable "vpc_name" {
  type        = string
  description = "VPC network name."
}

variable "controller_subnet_name" {
  type        = string
  description = "Subnet name for controllers."
}

#------------------------------------------------------------------------------
# Boundary Configuration
#------------------------------------------------------------------------------

variable "boundary_version" {
  type        = string
  description = "Boundary Enterprise version."
  default     = "0.21.0+ent"
}

variable "controller_instance_count" {
  type        = number
  description = "Number of controller instances."
  default     = 1
}

variable "controller_machine_type" {
  type        = string
  description = "Machine type for controller instances."
  default     = "n2-standard-4"
}

variable "ingress_worker_instance_count" {
  type        = number
  description = "Number of ingress worker instances."
  default     = 1
}

variable "egress_worker_instance_count" {
  type        = number
  description = "Number of egress worker instances."
  default     = 1
}

variable "deploy_ingress_worker" {
  type        = bool
  description = "Deploy ingress worker."
  default     = true
}

variable "deploy_egress_worker" {
  type        = bool
  description = "Deploy egress worker."
  default     = false
}

#------------------------------------------------------------------------------
# Load Balancing
#------------------------------------------------------------------------------

variable "api_load_balancing_scheme" {
  type        = string
  description = "Load balancer scheme for the API: 'internal' or 'external'."
  default     = "internal"

  validation {
    condition     = contains(["external", "internal"], var.api_load_balancing_scheme)
    error_message = "Must be 'external' or 'internal'."
  }
}

#------------------------------------------------------------------------------
# Naming
#------------------------------------------------------------------------------

variable "friendly_name_prefix" {
  type        = string
  description = "Prefix for resource names."
  default     = "bnd"
}

variable "goog_cm_deployment_name" {
  type        = string
  description = "GCP Marketplace deployment name."
  default     = ""
}
