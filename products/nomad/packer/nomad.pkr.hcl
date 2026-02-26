# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Packer Template for HashiCorp Nomad Enterprise - GCP Marketplace
#------------------------------------------------------------------------------

packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

#------------------------------------------------------------------------------
# Variables
#------------------------------------------------------------------------------

variable "project_id" {
  type        = string
  description = "GCP project ID to build the image in"
}

variable "zone" {
  type        = string
  description = "GCP zone to build the image in"
  default     = "us-central1-a"
}

variable "nomad_version" {
  type        = string
  description = "Nomad Enterprise version to install"
  default     = "1.11.2+ent"
}

variable "image_name" {
  type        = string
  description = "Name for the output image"
  default     = ""
}

variable "image_family" {
  type        = string
  description = "Image family for the output image"
  default     = "nomad-enterprise"
}

variable "marketplace_license" {
  type        = string
  description = "GCP Marketplace license to attach to the image"
  default     = "projects/ibm-software-mp-project/global/licenses/REPLACE_WITH_LICENSE_ID"
}

variable "source_image_family" {
  type        = string
  description = "Source image family to use as base"
  default     = "ubuntu-2204-lts"
}

variable "source_image_project" {
  type        = string
  description = "Project containing the source image"
  default     = "ubuntu-os-cloud"
}

variable "machine_type" {
  type        = string
  description = "Machine type for the build instance"
  default     = "n2-standard-2"
}

variable "disk_size" {
  type        = number
  description = "Disk size in GB for the build instance"
  default     = 50
}

variable "ssh_username" {
  type        = string
  description = "SSH username for provisioning"
  default     = "packer"
}

#------------------------------------------------------------------------------
# Locals
#------------------------------------------------------------------------------

locals {
  # Extract version without +ent suffix for image naming
  nomad_version_clean = replace(var.nomad_version, "+ent", "")

  # Version with dashes for labels (GCP labels don't allow dots)
  nomad_version_label = replace(local.nomad_version_clean, ".", "-")

  # Version formatted for image name (v1112 from 1.11.2)
  nomad_version_short = "v${replace(local.nomad_version_clean, ".", "")}"

  # Build date for image name
  build_date = formatdate("YYYYMMDD", timestamp())

  # GCP Marketplace image naming format: who-vmOS-image-architecture-date
  # Example: hashicorp-ubuntu2204-nomad-x86-64-v1112-20260224
  image_name = var.image_name != "" ? var.image_name : "hashicorp-ubuntu2204-nomad-x86-64-${local.nomad_version_short}-${local.build_date}"

  # Image labels (values must match regex ^[\p{Ll}0-9_-]{0,63}$)
  image_labels = {
    "nomad-version" = local.nomad_version_label
    "managed-by"    = "packer"
    "product"       = "nomad-enterprise"
    "marketplace"   = "true"
  }
}

#------------------------------------------------------------------------------
# Source: GCP Compute Image
#------------------------------------------------------------------------------

source "googlecompute" "nomad" {
  project_id          = var.project_id
  zone                = var.zone
  machine_type        = var.machine_type
  source_image_family = var.source_image_family
  source_image_project_id = [var.source_image_project]

  # Output image configuration
  image_name        = local.image_name
  image_family      = var.image_family
  image_description = "HashiCorp Nomad Enterprise ${var.nomad_version} - GCP Marketplace"
  image_labels      = local.image_labels

  # Attach Marketplace license
  image_licenses = [var.marketplace_license]

  # Disk configuration
  disk_size = var.disk_size
  disk_type = "pd-ssd"

  # SSH configuration
  ssh_username = var.ssh_username

  # Network configuration
  network    = "default"
  subnetwork = "default"

  # Use internal IP + IAP tunnel (required by org policy blocking external IPs)
  use_internal_ip = true
  omit_external_ip = true
  use_iap          = true

  # Tags for firewall rules
  tags = ["packer-build"]
}

#------------------------------------------------------------------------------
# Build
#------------------------------------------------------------------------------

build {
  sources = ["source.googlecompute.nomad"]

  # Upload installation script
  provisioner "file" {
    source      = "scripts/install-nomad.sh"
    destination = "/tmp/install-nomad.sh"
  }

  # Install Nomad Enterprise
  provisioner "shell" {
    inline = [
      "chmod +x /tmp/install-nomad.sh",
      "sudo NOMAD_VERSION=${var.nomad_version} /tmp/install-nomad.sh"
    ]
  }

  # Clean up for Marketplace compliance
  provisioner "shell" {
    inline = [
      "# Clean up temporary files",
      "sudo rm -rf /tmp/*",
      "sudo rm -rf /var/tmp/*",

      "# Clean up apt cache",
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",

      "# Remove SSH host keys (will be regenerated on first boot)",
      "sudo rm -f /etc/ssh/ssh_host_*",

      "# Clear machine-id (will be regenerated on first boot)",
      "sudo truncate -s 0 /etc/machine-id",

      "# Clear bash history (truncate file, history -c not available in sh)",
      "cat /dev/null > ~/.bash_history",

      "# Clear cloud-init data",
      "sudo cloud-init clean --logs",

      "# Sync filesystem",
      "sync"
    ]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
