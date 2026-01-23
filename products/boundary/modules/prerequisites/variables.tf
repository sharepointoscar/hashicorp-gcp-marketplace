# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "friendly_name_prefix" {
  type        = string
  description = "Prefix for secret names."
  default     = ""
}

variable "boundary_fqdn" {
  type        = string
  description = "FQDN for Boundary (used in self-signed certificate)."
}

variable "license_file_path" {
  type        = string
  description = "Path to the Boundary Enterprise license file (.hclic)."
}

variable "tls_cert_path" {
  type        = string
  description = "Path to TLS certificate file. If null, a self-signed cert is generated."
  default     = null
}

variable "tls_key_path" {
  type        = string
  description = "Path to TLS private key file. If null, a self-signed key is generated."
  default     = null
}

variable "tls_ca_bundle_path" {
  type        = string
  description = "Path to CA bundle file. Optional."
  default     = null
}

variable "labels" {
  type        = map(string)
  description = "Labels to apply to secrets."
  default     = {}
}
