# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GCP region for GCS bucket location."
  default     = "us-central1"
}

variable "friendly_name_prefix" {
  type        = string
  description = "Prefix for secret and resource names."
  default     = ""
}

variable "nomad_fqdn" {
  type        = string
  description = "FQDN for Nomad (used in self-signed certificate SAN)."
}

variable "nomad_datacenter" {
  type        = string
  description = "Nomad datacenter name (used in self-signed certificate SAN)."
  default     = "dc1"
}

variable "nomad_region" {
  type        = string
  description = "Nomad region name (used in self-signed certificate SAN for server hostname verification)."
  default     = "global"
}

variable "license_file_path" {
  type        = string
  description = "Path to the Nomad Enterprise license file (.hclic)."
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

variable "create_snapshot_bucket" {
  type        = bool
  description = "Whether to create a GCS bucket for Nomad Raft snapshots."
  default     = true
}

variable "labels" {
  type        = map(string)
  description = "Labels to apply to secrets and resources."
  default     = {}
}
