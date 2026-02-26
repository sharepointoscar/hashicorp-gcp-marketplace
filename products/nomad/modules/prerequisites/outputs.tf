# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "license_secret_name" {
  description = "Secret Manager secret name for Nomad license."
  value       = google_secret_manager_secret.license.secret_id
}

output "tls_cert_secret_name" {
  description = "Secret Manager secret name for TLS certificate."
  value       = google_secret_manager_secret.tls_cert.secret_id
}

output "tls_key_secret_name" {
  description = "Secret Manager secret name for TLS private key."
  value       = google_secret_manager_secret.tls_key.secret_id
}

output "ca_bundle_secret_name" {
  description = "Secret Manager secret name for CA bundle (null if not created)."
  value       = var.tls_ca_bundle_path != null ? google_secret_manager_secret.ca_bundle[0].secret_id : null
}

output "gossip_key_secret_name" {
  description = "Secret Manager secret name for gossip encryption key."
  value       = google_secret_manager_secret.gossip_key.secret_id
}

output "snapshot_bucket_name" {
  description = "GCS bucket name for Nomad snapshots (null if not created)."
  value       = var.create_snapshot_bucket ? google_storage_bucket.snapshots[0].name : null
}
