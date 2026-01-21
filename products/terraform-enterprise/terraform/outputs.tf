# outputs.tf - Output values
# HashiCorp Terraform Enterprise - GCP Marketplace (Infrastructure Only)

# -----------------------------------------------------------------------------
# Marketplace Inputs
# -----------------------------------------------------------------------------
# Use these values when deploying TFE via GCP Marketplace

output "marketplace_inputs" {
  description = "Values to use when deploying TFE via GCP Marketplace"
  value = {
    databaseHost        = module.infrastructure.database_host
    databaseName        = module.infrastructure.database_name
    databaseUser        = module.infrastructure.database_user
    databasePassword    = module.infrastructure.database_password
    redisHost           = module.infrastructure.redis_host
    redisPassword       = module.infrastructure.redis_password
    objectStorageBucket = module.infrastructure.gcs_bucket
    objectStorageProject = var.project_id
  }
  sensitive = true
}

# -----------------------------------------------------------------------------
# Infrastructure Outputs
# -----------------------------------------------------------------------------

output "database_instance" {
  description = "Cloud SQL instance name"
  value       = module.infrastructure.database_instance_name
}

output "database_connection_name" {
  description = "Cloud SQL connection name"
  value       = module.infrastructure.database_connection_name
}

output "database_host" {
  description = "Cloud SQL private IP"
  value       = module.infrastructure.database_host
}

output "redis_instance" {
  description = "Memorystore Redis instance name"
  value       = module.infrastructure.redis_instance_name
}

output "redis_host" {
  description = "Memorystore Redis private IP"
  value       = module.infrastructure.redis_host
}

output "gcs_bucket" {
  description = "GCS bucket name for TFE object storage"
  value       = module.infrastructure.gcs_bucket
}

# -----------------------------------------------------------------------------
# GKE Cluster
# -----------------------------------------------------------------------------

output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = data.google_container_cluster.primary.name
}

output "gke_cluster_location" {
  description = "GKE cluster location"
  value       = data.google_container_cluster.primary.location
}
