# helm.tf - Helm release for TFE
# HashiCorp Terraform Enterprise - GCP Marketplace

# -----------------------------------------------------------------------------
# Helm Provider
# -----------------------------------------------------------------------------

provider "helm" {
  kubernetes {
    host                   = "https://${data.google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "tfe" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "terraform-enterprise"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# TLS Secret
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "tfe_tls" {
  metadata {
    name      = "terraform-enterprise-certificates"
    namespace = kubernetes_namespace.tfe.metadata[0].name
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = base64decode(var.tls_certificate)
    "tls.key" = base64decode(var.tls_private_key)
    "ca.crt"  = base64decode(var.ca_certificate)
  }
}

# -----------------------------------------------------------------------------
# Helm Release Name
# -----------------------------------------------------------------------------

locals {
  helm_release_name = coalesce(var.helm_release_name, "tfe-${random_string.suffix.result}")
}

# -----------------------------------------------------------------------------
# TFE Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "tfe" {
  name       = local.helm_release_name
  namespace  = kubernetes_namespace.tfe.metadata[0].name
  repository = var.helm_chart_repo
  chart      = var.helm_chart_name
  version    = var.helm_chart_version

  wait          = true
  wait_for_jobs = true
  timeout       = 900 # 15 minutes for TFE startup

  # Replica count
  set {
    name  = "replicaCount"
    value = var.replica_count
  }

  # Image configuration (GCP Marketplace image replacement)
  set {
    name  = "image.repository"
    value = var.tfe_image_repo
  }

  set {
    name  = "image.tag"
    value = var.tfe_image_tag
  }

  # Override the default image.name (hashicorp/terraform-enterprise)
  # since our GCP Marketplace image already has the full path in tfe_image_repo
  set {
    name  = "image.name"
    value = ""
  }

  set {
    name  = "image.pullPolicy"
    value = "IfNotPresent"
  }

  # imagePullSecrets: GCP Marketplace images are public, no secrets needed
  # Default in values.yaml is already: imagePullSecrets: []

  # TLS configuration
  set {
    name  = "tls.certificateSecret"
    value = kubernetes_secret.tfe_tls.metadata[0].name
  }

  # TFE hostname
  set {
    name  = "env.variables.TFE_HOSTNAME"
    value = var.tfe_hostname
  }

  # Database configuration (from infrastructure module)
  set {
    name  = "env.variables.TFE_DATABASE_HOST"
    value = module.infrastructure.database_host
  }

  set {
    name  = "env.variables.TFE_DATABASE_NAME"
    value = module.infrastructure.database_name
  }

  set {
    name  = "env.variables.TFE_DATABASE_USER"
    value = module.infrastructure.database_user
  }

  set_sensitive {
    name  = "env.secrets.TFE_DATABASE_PASSWORD"
    value = module.infrastructure.database_password
  }

  # Database SSL (Cloud SQL requires SSL)
  set {
    name  = "env.variables.TFE_DATABASE_PARAMETERS"
    value = "sslmode=require"
  }

  # Redis configuration (from infrastructure module)
  set {
    name  = "env.variables.TFE_REDIS_HOST"
    value = module.infrastructure.redis_host
  }

  set {
    name  = "env.variables.TFE_REDIS_USE_TLS"
    value = "false"
  }

  set {
    name  = "env.variables.TFE_REDIS_USE_AUTH"
    value = "true"
  }

  set_sensitive {
    name  = "env.secrets.TFE_REDIS_PASSWORD"
    value = module.infrastructure.redis_password
  }

  # GCS object storage (from infrastructure module)
  set {
    name  = "env.variables.TFE_OBJECT_STORAGE_TYPE"
    value = "google"
  }

  set {
    name  = "env.variables.TFE_OBJECT_STORAGE_GOOGLE_BUCKET"
    value = module.infrastructure.gcs_bucket
  }

  set {
    name  = "env.variables.TFE_OBJECT_STORAGE_GOOGLE_PROJECT"
    value = var.project_id
  }

  # License and encryption
  set_sensitive {
    name  = "env.secrets.TFE_LICENSE"
    value = var.tfe_license
  }

  set_sensitive {
    name  = "env.secrets.TFE_ENCRYPTION_PASSWORD"
    value = var.tfe_encryption_password
  }

  # Service configuration
  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  depends_on = [
    kubernetes_secret.tfe_tls,
    module.infrastructure,
  ]
}
