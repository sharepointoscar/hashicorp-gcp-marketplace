# outputs.tf - Output values
# HashiCorp Terraform Enterprise - GCP Marketplace

# -----------------------------------------------------------------------------
# TFE Access
# -----------------------------------------------------------------------------

output "tfe_url" {
  description = "TFE application URL"
  value       = "https://${var.tfe_hostname}"
}

output "tfe_namespace" {
  description = "Kubernetes namespace where TFE is deployed"
  value       = kubernetes_namespace.tfe.metadata[0].name
}

output "helm_release_name" {
  description = "Name of the Helm release"
  value       = helm_release.tfe.name
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

output "redis_instance" {
  description = "Memorystore Redis instance name"
  value       = module.infrastructure.redis_instance_name
}

output "gcs_bucket" {
  description = "GCS bucket name for TFE object storage"
  value       = module.infrastructure.gcs_bucket
}

# -----------------------------------------------------------------------------
# Health Check
# -----------------------------------------------------------------------------

output "health_check_command" {
  description = "Command to check TFE health"
  value       = "curl -k https://${var.tfe_hostname}/_health_check"
}
