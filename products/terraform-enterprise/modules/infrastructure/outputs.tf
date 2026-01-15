# modules/infrastructure/outputs.tf
# Output values for infrastructure module

# -----------------------------------------------------------------------------
# Cloud SQL Outputs
# -----------------------------------------------------------------------------

output "database_host" {
  description = "Cloud SQL private IP address with port"
  value       = "${google_sql_database_instance.tfe.private_ip_address}:5432"
}

output "database_name" {
  description = "Database name"
  value       = google_sql_database.tfe.name
}

output "database_user" {
  description = "Database username"
  value       = google_sql_user.tfe.name
}

output "database_password" {
  description = "Database password"
  value       = random_password.database.result
  sensitive   = true
}

output "database_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.tfe.name
}

output "database_connection_name" {
  description = "Cloud SQL connection name for Cloud SQL Proxy"
  value       = google_sql_database_instance.tfe.connection_name
}

# -----------------------------------------------------------------------------
# Redis Outputs
# -----------------------------------------------------------------------------

output "redis_host" {
  description = "Redis host with port"
  value       = "${google_redis_instance.tfe.host}:${google_redis_instance.tfe.port}"
}

output "redis_password" {
  description = "Redis AUTH password"
  value       = google_redis_instance.tfe.auth_string
  sensitive   = true
}

output "redis_instance_name" {
  description = "Redis instance name"
  value       = google_redis_instance.tfe.name
}

# -----------------------------------------------------------------------------
# GCS Outputs
# -----------------------------------------------------------------------------

output "gcs_bucket" {
  description = "GCS bucket name"
  value       = google_storage_bucket.tfe.name
}

# -----------------------------------------------------------------------------
# Service Account Outputs
# -----------------------------------------------------------------------------

output "service_account_email" {
  description = "TFE service account email"
  value       = google_service_account.tfe.email
}
