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
  }
}
