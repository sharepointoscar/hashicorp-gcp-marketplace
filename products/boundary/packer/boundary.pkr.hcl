# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Packer Template for HashiCorp Boundary Enterprise - GCP Marketplace
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

variable "boundary_version" {
  type        = string
  description = "Boundary Enterprise version to install"
  default     = "0.21.0+ent"
}

variable "image_name" {
  type        = string
  description = "Name for the output image"
  default     = ""
}

variable "image_family" {
  type        = string
  description = "Image family for the output image"
  default     = "boundary-enterprise"
}

variable "marketplace_license" {
  type        = string
  description = "GCP Marketplace license to attach to the image"
  default     = "projects/ibm-software-mp-project-test/global/licenses/cloud-marketplace-a515e71bc1c469c1-df1ebeb69c0ba664"
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
  boundary_version_clean = replace(var.boundary_version, "+ent", "")

  # Version with dashes for labels (GCP labels don't allow dots)
  boundary_version_label = replace(local.boundary_version_clean, ".", "-")

  # Version formatted for image name (v0210 from 0.21.0)
  boundary_version_short = "v${replace(local.boundary_version_clean, ".", "")}"

  # Build date for image name
  build_date = formatdate("YYYYMMDD", timestamp())

  # GCP Marketplace image naming format: who-vmOS-image-architecture-date
  # Example: hashicorp-ubuntu2204-boundary-x86-64-v0210-20260118
  image_name = var.image_name != "" ? var.image_name : "hashicorp-ubuntu2204-boundary-x86-64-${local.boundary_version_short}-${local.build_date}"

  # Image labels (values must match regex ^[\p{Ll}0-9_-]{0,63}$)
  image_labels = {
    "boundary-version" = local.boundary_version_label
    "managed-by"       = "packer"
    "product"          = "boundary-enterprise"
    "marketplace"      = "true"
  }
}

#------------------------------------------------------------------------------
# Source: GCP Compute Image
#------------------------------------------------------------------------------

source "googlecompute" "boundary" {
  project_id          = var.project_id
  zone                = var.zone
  machine_type        = var.machine_type
  source_image_family = var.source_image_family
  source_image_project_id = [var.source_image_project]

  # Output image configuration
  image_name        = local.image_name
  image_family      = var.image_family
  image_description = "HashiCorp Boundary Enterprise ${var.boundary_version} - GCP Marketplace"
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

  # Use internal IP if no external IP available
  use_internal_ip = false

  # Tags for firewall rules
  tags = ["packer-build"]
}

#------------------------------------------------------------------------------
# Build
#------------------------------------------------------------------------------

build {
  sources = ["source.googlecompute.boundary"]

  # Upload installation script
  provisioner "file" {
    source      = "scripts/install-boundary.sh"
    destination = "/tmp/install-boundary.sh"
  }

  # Install Boundary Enterprise
  provisioner "shell" {
    inline = [
      "chmod +x /tmp/install-boundary.sh",
      "sudo BOUNDARY_VERSION=${var.boundary_version} /tmp/install-boundary.sh"
    ]
  }

  # Upload startup script template
  provisioner "file" {
    source      = "scripts/startup-script.sh"
    destination = "/tmp/startup-script.sh"
  }

  # Install startup script
  provisioner "shell" {
    inline = [
      "sudo mv /tmp/startup-script.sh /opt/boundary/startup-script.sh",
      "sudo chmod +x /opt/boundary/startup-script.sh"
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
