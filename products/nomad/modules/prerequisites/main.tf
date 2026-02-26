# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Nomad Enterprise Prerequisites
#
# This module creates all required prerequisites for the Nomad HVD server module:
# - Nomad Enterprise license (from file → Secret Manager)
# - TLS certificate and private key (self-signed or provided → Secret Manager)
# - TLS CA bundle (optional → Secret Manager)
# - Gossip encryption key (auto-generated → Secret Manager)
# - GCS bucket for Raft snapshots (optional)
#------------------------------------------------------------------------------

locals {
  secret_prefix = var.friendly_name_prefix != "" ? "${var.friendly_name_prefix}-" : ""
}

#------------------------------------------------------------------------------
# Gossip Encryption Key (auto-generated)
#------------------------------------------------------------------------------
resource "random_id" "gossip_key" {
  byte_length = 32
}

#------------------------------------------------------------------------------
# Self-Signed TLS Certificate (if not provided)
#------------------------------------------------------------------------------
resource "tls_private_key" "nomad" {
  count = var.tls_cert_path == null ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "nomad" {
  count = var.tls_cert_path == null ? 1 : 0

  private_key_pem = tls_private_key.nomad[0].private_key_pem

  subject {
    common_name         = var.nomad_fqdn
    organization        = "HashiCorp"
    organizational_unit = "Nomad Enterprise"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
  ]

  dns_names = [
    var.nomad_fqdn,
    "*.${var.nomad_fqdn}",
    "server.${var.nomad_region}.nomad",
    "server.${var.nomad_datacenter}.nomad",
    "localhost",
  ]

  ip_addresses = ["127.0.0.1"]
}

#------------------------------------------------------------------------------
# Secret Manager - Nomad License
#------------------------------------------------------------------------------
resource "google_secret_manager_secret" "license" {
  project   = var.project_id
  secret_id = "${local.secret_prefix}nomad-license"

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "license" {
  secret      = google_secret_manager_secret.license.id
  secret_data = file(var.license_file_path)
}

#------------------------------------------------------------------------------
# Secret Manager - TLS Certificate (base64 encoded for cloud-init)
#------------------------------------------------------------------------------
resource "google_secret_manager_secret" "tls_cert" {
  project   = var.project_id
  secret_id = "${local.secret_prefix}nomad-tls-cert"

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "tls_cert" {
  secret      = google_secret_manager_secret.tls_cert.id
  secret_data = base64encode(var.tls_cert_path != null ? file(var.tls_cert_path) : tls_self_signed_cert.nomad[0].cert_pem)
}

#------------------------------------------------------------------------------
# Secret Manager - TLS Private Key (base64 encoded for cloud-init)
#------------------------------------------------------------------------------
resource "google_secret_manager_secret" "tls_key" {
  project   = var.project_id
  secret_id = "${local.secret_prefix}nomad-tls-key"

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "tls_key" {
  secret      = google_secret_manager_secret.tls_key.id
  secret_data = base64encode(var.tls_key_path != null ? file(var.tls_key_path) : tls_private_key.nomad[0].private_key_pem)
}

#------------------------------------------------------------------------------
# Secret Manager - CA Bundle (optional, base64 encoded for cloud-init)
#------------------------------------------------------------------------------
resource "google_secret_manager_secret" "ca_bundle" {
  count = var.tls_ca_bundle_path != null ? 1 : 0

  project   = var.project_id
  secret_id = "${local.secret_prefix}nomad-ca-bundle"

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "ca_bundle" {
  count = var.tls_ca_bundle_path != null ? 1 : 0

  secret      = google_secret_manager_secret.ca_bundle[0].id
  secret_data = base64encode(file(var.tls_ca_bundle_path))
}

#------------------------------------------------------------------------------
# Secret Manager - Gossip Encryption Key
#------------------------------------------------------------------------------
resource "google_secret_manager_secret" "gossip_key" {
  project   = var.project_id
  secret_id = "${local.secret_prefix}nomad-gossip-key"

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "gossip_key" {
  secret      = google_secret_manager_secret.gossip_key.id
  secret_data = random_id.gossip_key.b64_std
}

#------------------------------------------------------------------------------
# GCS Bucket - Nomad Raft Snapshots (optional)
#------------------------------------------------------------------------------
resource "google_storage_bucket" "snapshots" {
  count = var.create_snapshot_bucket ? 1 : 0

  name          = "${local.secret_prefix}nomad-snapshots-${var.project_id}"
  project       = var.project_id
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  labels = var.labels

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 90
    }
  }
}
