# versions.tf - Terraform and provider requirements
# HashiCorp Terraform Enterprise - GCP Marketplace (Infrastructure Only)
#
# This Terraform configuration provisions infrastructure for TFE:
# - Cloud SQL PostgreSQL
# - Memorystore Redis
# - GCS bucket
#
# TFE itself is deployed via GCP Marketplace (mpdev deployer).

terraform {
  required_version = "~> 1.3"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.32"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.32"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  provider_meta "google" {
    module_name = "blueprints/terraform/canonical-mp/v0.0.1"
  }
}
