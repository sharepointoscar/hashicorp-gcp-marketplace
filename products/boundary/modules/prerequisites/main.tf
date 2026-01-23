# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Boundary Enterprise Prerequisites
#
# This module creates all required secrets and certificates for Boundary:
# - Boundary Enterprise license (from file)
# - TLS certificate and private key (self-signed or provided)
# - Database password (random generated)
#------------------------------------------------------------------------------

locals {
  secret_prefix = var.friendly_name_prefix != "" ? "${var.friendly_name_prefix}-" : ""
}

#------------------------------------------------------------------------------
# Random Database Password
#------------------------------------------------------------------------------
resource "random_password" "database" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

#------------------------------------------------------------------------------
# Self-Signed TLS Certificate (if not provided)
#------------------------------------------------------------------------------
resource "tls_private_key" "boundary" {
  count = var.tls_cert_path == null ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "boundary" {
  count = var.tls_cert_path == null ? 1 : 0

  private_key_pem = tls_private_key.boundary[0].private_key_pem

  subject {
    common_name         = var.boundary_fqdn
    organization        = "HashiCorp"
    organizational_unit = "Boundary Enterprise"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  dns_names = [
    var.boundary_fqdn,
    "*.${var.boundary_fqdn}",
  ]

  ip_addresses = ["127.0.0.1"]
}

#------------------------------------------------------------------------------
# Secret Manager - Boundary License
#------------------------------------------------------------------------------
resource "google_secret_manager_secret" "license" {
  project   = var.project_id
  secret_id = "${local.secret_prefix}boundary-license"

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
# Secret Manager - TLS Certificate
#------------------------------------------------------------------------------
resource "google_secret_manager_secret" "tls_cert" {
  project   = var.project_id
  secret_id = "${local.secret_prefix}boundary-tls-cert"

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "tls_cert" {
  secret = google_secret_manager_secret.tls_cert.id
  secret_data = var.tls_cert_path != null ? file(var.tls_cert_path) : tls_self_signed_cert.boundary[0].cert_pem
}

#------------------------------------------------------------------------------
# Secret Manager - TLS Private Key
#------------------------------------------------------------------------------
resource "google_secret_manager_secret" "tls_key" {
  project   = var.project_id
  secret_id = "${local.secret_prefix}boundary-tls-key"

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "tls_key" {
  secret = google_secret_manager_secret.tls_key.id
  secret_data = var.tls_key_path != null ? file(var.tls_key_path) : tls_private_key.boundary[0].private_key_pem
}

#------------------------------------------------------------------------------
# Secret Manager - Database Password
#------------------------------------------------------------------------------
resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = "${local.secret_prefix}boundary-db-password"

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.database.result
}

#------------------------------------------------------------------------------
# Secret Manager - CA Bundle (optional)
#------------------------------------------------------------------------------
resource "google_secret_manager_secret" "ca_bundle" {
  count = var.tls_ca_bundle_path != null ? 1 : 0

  project   = var.project_id
  secret_id = "${local.secret_prefix}boundary-ca-bundle"

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "ca_bundle" {
  count = var.tls_ca_bundle_path != null ? 1 : 0

  secret      = google_secret_manager_secret.ca_bundle[0].id
  secret_data = file(var.tls_ca_bundle_path)
}
