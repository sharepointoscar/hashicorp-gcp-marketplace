# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Boundary Controller Outputs
#------------------------------------------------------------------------------

output "boundary_url" {
  description = "URL to access Boundary API and UI."
  value       = "https://${var.boundary_fqdn}:9200"
}

output "boundary_fqdn" {
  description = "Fully qualified domain name for Boundary."
  value       = var.boundary_fqdn
}

output "controller_load_balancer_ip" {
  description = "IP address of the controller load balancer."
  value       = module.controller.api_lb_ip_address
}

#------------------------------------------------------------------------------
# Worker Outputs
#------------------------------------------------------------------------------

output "ingress_worker_lb_ip" {
  description = "IP address of the ingress worker load balancer."
  value       = var.deploy_ingress_worker ? module.ingress_worker[0].proxy_lb_ip_address : null
}

#------------------------------------------------------------------------------
# Database Outputs
#------------------------------------------------------------------------------

output "database_instance_id" {
  description = "ID of the Cloud SQL PostgreSQL instance."
  value       = module.controller.google_sql_database_instance_id
}

output "database_private_ip" {
  description = "Private IP address of the Cloud SQL instance."
  value       = module.controller.gcp_db_instance_ip
}

#------------------------------------------------------------------------------
# KMS Outputs
#------------------------------------------------------------------------------

output "key_ring_name" {
  description = "Name of the Cloud KMS key ring."
  value       = module.controller.created_boundary_keyring_name
}

output "root_key_name" {
  description = "Name of the Boundary root KMS key."
  value       = module.controller.created_boundary_root_key_name
}

output "worker_key_name" {
  description = "Name of the Boundary worker KMS key."
  value       = module.controller.created_boundary_worker_key_name
}

output "recovery_key_name" {
  description = "Name of the Boundary recovery KMS key."
  value       = module.controller.created_boundary_recovery_key_name
}

#------------------------------------------------------------------------------
# Storage Outputs (BSR)
#------------------------------------------------------------------------------

output "bsr_bucket_name" {
  description = "Name of the GCS bucket for session recording (if enabled)."
  value       = var.enable_session_recording ? module.controller.bsr_bucket_name : null
}

#------------------------------------------------------------------------------
# Deployment Information
#------------------------------------------------------------------------------

output "deployment_id" {
  description = "Unique deployment identifier."
  value       = local.name_prefix
}

output "boundary_version" {
  description = "Deployed Boundary Enterprise version."
  value       = var.boundary_version
}

output "region" {
  description = "GCP region where Boundary is deployed."
  value       = var.region
}

#------------------------------------------------------------------------------
# Post-Deployment Instructions
#------------------------------------------------------------------------------

output "post_deployment_instructions" {
  description = "Instructions for accessing Boundary after deployment."
  value       = <<-EOT

    ============================================================
    HashiCorp Boundary Enterprise Deployment Complete
    ============================================================

    Boundary URL: https://${var.boundary_fqdn}:9200

    Controller Load Balancer IP: ${module.controller.api_lb_ip_address}

    NEXT STEPS:
    -----------
    1. Ensure DNS record for '${var.boundary_fqdn}' points to ${module.controller.api_lb_ip_address}

    2. The API should be available immediately after terraform apply completes.
       The managed instance group health check ensures controllers are healthy
       before Terraform finishes (~3-5 min for Cloud SQL + ~1 min for controller boot).

    3. Database initialization runs automatically via cloud-init on the first controller boot.
       Check the controller serial console for initial admin credentials:
       gcloud compute instances get-serial-port-output <controller-instance> --project=${var.project_id}

    4. Verify the API is responding:
       curl -sk https://${module.controller.api_lb_ip_address}:9200/v1/scopes

    5. Access the Boundary UI:
       https://${var.boundary_fqdn}:9200

    6. Install the Boundary CLI:
       https://developer.hashicorp.com/boundary/install

    7. Authenticate:
       export BOUNDARY_ADDR="https://${var.boundary_fqdn}:9200"
       boundary authenticate

    SUPPORT:
    --------
    - Documentation: https://developer.hashicorp.com/boundary/docs
    - Support: https://support.hashicorp.com

    ============================================================
  EOT
}
