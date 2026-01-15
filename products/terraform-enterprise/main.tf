# main.tf - Main Terraform configuration
# HashiCorp Terraform Enterprise - GCP Marketplace

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

provider "google" {
  project = var.project_id
}

provider "google-beta" {
  project = var.project_id
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "google_client_config" "default" {}

data "google_project" "project" {
  project_id = var.project_id
}

# -----------------------------------------------------------------------------
# Enable Required APIs
# -----------------------------------------------------------------------------

module "project_services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 17.0"

  project_id = var.project_id

  activate_apis = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "redis.googleapis.com",
    "storage.googleapis.com",
    "servicenetworking.googleapis.com",
    "iam.googleapis.com",
  ]

  disable_services_on_destroy = false
}

# -----------------------------------------------------------------------------
# Random Suffix for Resource Names
# -----------------------------------------------------------------------------

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

# -----------------------------------------------------------------------------
# Infrastructure Module (Cloud SQL, Redis, GCS)
# -----------------------------------------------------------------------------

module "infrastructure" {
  source = "./modules/infrastructure"

  project_id       = var.project_id
  region           = var.region
  network_name     = var.network_name
  subnetwork_name  = var.subnetwork_name
  name_prefix      = "tfe-${random_string.suffix.result}"

  # Cloud SQL Configuration
  database_tier    = var.database_tier
  database_version = var.database_version

  # GCS Configuration
  gcs_location = var.gcs_location

  # Private Service Access (set to false if already exists in VPC)
  create_private_service_access = var.create_private_service_access

  depends_on = [module.project_services]
}
