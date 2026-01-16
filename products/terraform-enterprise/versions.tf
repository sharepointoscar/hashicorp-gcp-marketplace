# versions.tf - Terraform and provider requirements
# HashiCorp Terraform Enterprise - GCP Marketplace

terraform {
  # GCP Infrastructure Manager supports: 1.5.7, 1.4.7, 1.3.10
  required_version = ">= 1.3"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.42"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.42"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
