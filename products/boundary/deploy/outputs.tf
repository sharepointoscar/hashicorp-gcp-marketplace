# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "boundary_url" {
  description = "URL to access Boundary."
  value       = module.boundary.boundary_url
}

output "controller_load_balancer_ip" {
  description = "Controller load balancer IP."
  value       = module.boundary.controller_load_balancer_ip
}

output "post_deployment_instructions" {
  description = "Post-deployment instructions."
  value       = module.boundary.post_deployment_instructions
}
