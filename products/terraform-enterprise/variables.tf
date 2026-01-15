# variables.tf - Input variables
# HashiCorp Terraform Enterprise - GCP Marketplace

# -----------------------------------------------------------------------------
# Project and Region
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

# -----------------------------------------------------------------------------
# GKE Cluster (Existing)
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of existing GKE cluster"
  type        = string
}

variable "cluster_location" {
  description = "Location (region or zone) of existing GKE cluster"
  type        = string
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "network_name" {
  description = "Name of VPC network"
  type        = string
  default     = "default"
}

variable "subnetwork_name" {
  description = "Name of VPC subnetwork"
  type        = string
  default     = "default"
}

# -----------------------------------------------------------------------------
# TFE Configuration
# -----------------------------------------------------------------------------

variable "namespace" {
  description = "Kubernetes namespace for TFE deployment"
  type        = string
  default     = "terraform-enterprise"
}

variable "helm_release_name" {
  description = "Name for the Helm release"
  type        = string
  default     = null
}

variable "tfe_hostname" {
  description = "Fully qualified domain name for TFE"
  type        = string
}

variable "replica_count" {
  description = "Number of TFE replicas"
  type        = number
  default     = 1
}

variable "tfe_license" {
  description = "TFE license key"
  type        = string
  sensitive   = true
}

variable "tfe_encryption_password" {
  description = "Encryption password for TFE data at rest (min 16 chars)"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# TLS Configuration
# -----------------------------------------------------------------------------

variable "tls_certificate" {
  description = "Base64-encoded TLS certificate"
  type        = string
  sensitive   = true
}

variable "tls_private_key" {
  description = "Base64-encoded TLS private key"
  type        = string
  sensitive   = true
}

variable "ca_certificate" {
  description = "Base64-encoded CA certificate bundle"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Helm Chart Configuration (set by GCP Marketplace)
# -----------------------------------------------------------------------------

variable "helm_chart_repo" {
  description = "Helm chart repository URL (OCI)"
  type        = string
  default     = "oci://us-docker.pkg.dev/ibm-software-mp-project-test/tfe-marketplace"
}

variable "helm_chart_name" {
  description = "Helm chart name"
  type        = string
  default     = "terraform-enterprise-chart"
}

variable "helm_chart_version" {
  description = "Helm chart version"
  type        = string
  default     = "1.1.3"
}

# -----------------------------------------------------------------------------
# Image Configuration (set by GCP Marketplace via schema.yaml)
# -----------------------------------------------------------------------------

variable "tfe_image_repo" {
  description = "TFE image repository (set by GCP Marketplace)"
  type        = string
}

variable "tfe_image_tag" {
  description = "TFE image tag (set by GCP Marketplace)"
  type        = string
}

variable "ubbagent_image_repo" {
  description = "UBB agent image repository (set by GCP Marketplace)"
  type        = string
}

variable "ubbagent_image_tag" {
  description = "UBB agent image tag (set by GCP Marketplace)"
  type        = string
}

# -----------------------------------------------------------------------------
# Infrastructure Configuration
# -----------------------------------------------------------------------------

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
  description = "Whether to create Private Service Access (set to false if it already exists in VPC). Most customers will have existing PSA."
  type        = bool
  default     = false
}
