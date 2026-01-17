# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "license_secret_id" {
  description = "Secret Manager secret ID for Boundary license."
  value       = google_secret_manager_secret.license.secret_id
}

output "tls_cert_secret_id" {
  description = "Secret Manager secret ID for TLS certificate."
  value       = google_secret_manager_secret.tls_cert.secret_id
}

output "tls_key_secret_id" {
  description = "Secret Manager secret ID for TLS private key."
  value       = google_secret_manager_secret.tls_key.secret_id
}

output "db_password_secret_id" {
  description = "Secret Manager secret ID for database password."
  value       = google_secret_manager_secret.db_password.secret_id
}

output "ca_bundle_secret_id" {
  description = "Secret Manager secret ID for CA bundle (if created)."
  value       = var.tls_ca_bundle_path != null ? google_secret_manager_secret.ca_bundle[0].secret_id : null
}

output "tls_cert_pem" {
  description = "TLS certificate in PEM format (for reference)."
  value       = var.tls_cert_path != null ? file(var.tls_cert_path) : tls_self_signed_cert.boundary[0].cert_pem
  sensitive   = true
}

output "database_password" {
  description = "Generated database password."
  value       = random_password.database.result
  sensitive   = true
}
