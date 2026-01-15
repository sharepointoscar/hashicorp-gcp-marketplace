# modules/infrastructure/variables.tf
# Input variables for infrastructure module

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
}

variable "network_name" {
  description = "Name of VPC network"
  type        = string
}

variable "subnetwork_name" {
  description = "Name of VPC subnetwork"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "database_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-custom-4-16384"
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL version"
  type        = string
  default     = "POSTGRES_16"
}

variable "gcs_location" {
  description = "GCS bucket location"
  type        = string
  default     = "US"
}

variable "create_private_service_access" {
  description = "Whether to create Private Service Access (set to false if it already exists)"
  type        = bool
  default     = true
}
