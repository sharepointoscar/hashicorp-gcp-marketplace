# Copyright IBM Corp. 2024, 2025
# SPDX-License-Identifier: MPL-2.0

data "google_kms_key_ring" "key_ring" {
  count = var.use_kms ? 1 : 0

  name     = var.key_ring_name
  location = var.key_ring_location != null || data.google_client_config.default.region != null ? var.key_ring_location != null ? var.key_ring_location : data.google_client_config.default.region : var.region
}

data "google_kms_crypto_key" "key" {
  count = var.use_kms ? 1 : 0

  name     = var.key_name
  key_ring = data.google_kms_key_ring.key_ring[0].id
}

#-----------------------------------------------------------------------------------
# Service Account
#-----------------------------------------------------------------------------------
resource "google_service_account" "boundary" {
  account_id   = "${var.friendly_name_prefix}-bnd-wk-svc-acct"
  display_name = "${var.friendly_name_prefix}-boundary-worker-svc-acct"
  description  = "Service Account allowing Boundary instance(s) to interact GCP resources and services."
}

# NOTE: google_service_account_key removed - VMs use attached SA via metadata server
# This avoids org policy: iam.managed.disableServiceAccountKeyCreation

#-----------------------------------------------------------------------------------
# KMS Manager
#-----------------------------------------------------------------------------------
resource "google_kms_crypto_key_iam_member" "worker_operator" {
  count = var.use_kms ? 1 : 0

  crypto_key_id = data.google_kms_crypto_key.key[0].id
  role          = "roles/cloudkms.cryptoOperator"
  member        = "serviceAccount:${google_service_account.boundary.email}"
}

resource "google_kms_crypto_key_iam_member" "worker_viewer" {
  count = var.use_kms ? 1 : 0

  crypto_key_id = data.google_kms_crypto_key.key[0].id
  role          = "roles/cloudkms.viewer"
  member        = "serviceAccount:${google_service_account.boundary.email}"
}

