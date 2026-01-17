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

variable "boundary_license_secret_id" {
  type        = string
  description = "Secret Manager secret ID for Boundary license."
}

variable "boundary_tls_cert_secret_id" {
  type        = string
  description = "Secret Manager secret ID for TLS certificate."
}

variable "boundary_tls_privkey_secret_id" {
  type        = string
  description = "Secret Manager secret ID for TLS private key."
}

variable "boundary_database_password_secret_id" {
  type        = string
  description = "Secret Manager secret ID for database password."
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
# Optional Variables
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

variable "goog_cm_deployment_name" {
  type        = string
  description = "GCP Marketplace deployment name."
  default     = "boundary-test"
}
