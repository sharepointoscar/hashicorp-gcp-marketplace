# modules/infrastructure/main.tf
# Infrastructure resources for Terraform Enterprise (Cloud SQL, Redis, GCS)

# -----------------------------------------------------------------------------
# Random Suffix for Unique Names
# -----------------------------------------------------------------------------

resource "random_password" "database" {
  length  = 24
  special = false
}

resource "random_password" "redis" {
  length  = 24
  special = false
}

# -----------------------------------------------------------------------------
# Service Networking (for Private Service Access)
# -----------------------------------------------------------------------------

data "google_compute_network" "network" {
  name    = var.network_name
  project = var.project_id
}

# Use existing Private Service Access if available, otherwise create new
resource "google_compute_global_address" "private_ip_range" {
  count         = var.create_private_service_access ? 1 : 0
  name          = "${var.name_prefix}-private-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = data.google_compute_network.network.id
  project       = var.project_id
}

resource "google_service_networking_connection" "private_service_connection" {
  count                   = var.create_private_service_access ? 1 : 0
  network                 = data.google_compute_network.network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range[0].name]
}

# -----------------------------------------------------------------------------
# Cloud SQL PostgreSQL
# -----------------------------------------------------------------------------

resource "google_sql_database_instance" "tfe" {
  name             = "${var.name_prefix}-postgres"
  database_version = var.database_version
  region           = var.region
  project          = var.project_id

  deletion_protection = false

  settings {
    tier              = var.database_tier
    availability_type = "REGIONAL"
    disk_autoresize   = true
    disk_size         = 100
    disk_type         = "PD_SSD"

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 7
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = data.google_compute_network.network.id
      # Use ssl_mode instead of require_ssl (deprecated)
      # ENCRYPTED_ONLY requires SSL but doesn't require client certificates
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    database_flags {
      name  = "max_connections"
      value = "256"
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 3
      update_track = "stable"
    }
  }

  # Only depend on PSA connection if we're creating it
  depends_on = [google_service_networking_connection.private_service_connection]

  lifecycle {
    ignore_changes = [settings[0].ip_configuration[0].private_network]
  }
}

resource "google_sql_database" "tfe" {
  name     = "tfe"
  instance = google_sql_database_instance.tfe.name
  project  = var.project_id
}

resource "google_sql_user" "tfe" {
  name     = "tfe"
  instance = google_sql_database_instance.tfe.name
  password = random_password.database.result
  project  = var.project_id
}

# -----------------------------------------------------------------------------
# Memorystore Redis
# -----------------------------------------------------------------------------

resource "google_redis_instance" "tfe" {
  name               = "${var.name_prefix}-redis"
  tier               = "STANDARD_HA"
  memory_size_gb     = 4
  region             = var.region
  project            = var.project_id
  authorized_network = data.google_compute_network.network.id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"
  redis_version      = "REDIS_7_0"
  display_name       = "TFE Redis"
  auth_enabled       = true

  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 3
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }

  depends_on = [google_service_networking_connection.private_service_connection]
}

# -----------------------------------------------------------------------------
# GCS Bucket for Object Storage
# -----------------------------------------------------------------------------

resource "google_storage_bucket" "tfe" {
  name          = "${var.name_prefix}-objects-${var.project_id}"
  location      = var.gcs_location
  project       = var.project_id
  force_destroy = true

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    app        = "terraform-enterprise"
    managed-by = "terraform"
  }
}

# -----------------------------------------------------------------------------
# IAM for Workload Identity (GCS access)
# -----------------------------------------------------------------------------

resource "google_service_account" "tfe" {
  account_id   = "${var.name_prefix}-sa"
  display_name = "TFE Service Account"
  project      = var.project_id
}

resource "google_storage_bucket_iam_member" "tfe_object_admin" {
  bucket = google_storage_bucket.tfe.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.tfe.email}"
}

resource "google_project_iam_member" "tfe_workload_identity" {
  project = var.project_id
  role    = "roles/iam.workloadIdentityUser"
  member  = "serviceAccount:${var.project_id}.svc.id.goog[terraform-enterprise/terraform-enterprise]"
}
