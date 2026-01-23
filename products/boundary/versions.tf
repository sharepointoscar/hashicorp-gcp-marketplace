# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

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
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3"
    }
  }

  provider_meta "google" {
    module_name = "blueprints/terraform/boundary-enterprise/v0.21.0"
  }
}
