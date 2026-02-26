# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Nomad URLs
#------------------------------------------------------------------------------
output "nomad_url" {
  description = "URL to access Nomad UI and API."
  value       = module.server.nomad_url
}

output "nomad_fqdn" {
  description = "Fully qualified domain name for Nomad."
  value       = var.nomad_fqdn
}

output "load_balancer_ip" {
  description = "IP address of the Nomad load balancer."
  value       = module.server.load_balancer_ip
}

#------------------------------------------------------------------------------
# Deployment Info
#------------------------------------------------------------------------------
output "deployment_id" {
  description = "Marketplace deployment name."
  value       = local.name_prefix
}

output "nomad_version" {
  description = "Deployed Nomad Enterprise version."
  value       = var.nomad_version
}

output "region" {
  description = "GCP region of the deployment."
  value       = var.region
}

output "snapshot_bucket" {
  description = "GCS bucket name for Nomad snapshots."
  value       = module.prerequisites.snapshot_bucket_name
}

#------------------------------------------------------------------------------
# CLI Configuration
#------------------------------------------------------------------------------
output "nomad_cli_config" {
  description = "Environment variables to configure the Nomad CLI."
  value       = module.server.nomad_cli_config
}

#------------------------------------------------------------------------------
# Post-Deployment Instructions
#------------------------------------------------------------------------------
output "post_deployment_instructions" {
  description = "Steps to complete after deployment."
  value       = <<-EOT
    ============================================================
    Nomad Enterprise Deployment Complete
    ============================================================

    Nomad URL: ${module.server.nomad_url}
    Region:    ${var.region}
    Nodes:     ${var.node_count}
    Version:   ${var.nomad_version}

    NEXT STEPS:

    1. Configure your Nomad CLI:
       ${module.server.nomad_cli_config}

    2. Bootstrap ACLs (first time only):
       nomad acl bootstrap

    3. Verify cluster health:
       nomad server members
       nomad node status

    4. Access the UI:
       Open ${module.server.nomad_url}/ui in your browser

    5. (Optional) Configure Raft snapshots:
       nomad operator snapshot save backup.snap

    ============================================================
  EOT
}
