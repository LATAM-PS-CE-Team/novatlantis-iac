# ==============================================================================
# MÓDULO TERRAFORM: ARTIFACT REGISTRY, SECRET MANAGER, WORKLOAD IAM & WIF GITHUB
# Repositório: LATAM-PS-CE-Team/novatlantis-iac (modules/security-iam-secrets)
# ==============================================================================

variable "project_id" {
  type        = string
  description = "ID do projeto Google Cloud"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "Região do Artifact Registry"
}

variable "github_owner" {
  type        = string
  default     = "LATAM-PS-CE-Team"
  description = "Organização GitHub autorizada no Workload Identity Federation (WIF)"
}

variable "ar_repo_name" {
  type        = string
  default     = "novatlantis-gov-repo"
  description = "Nome do repositório Docker no Artifact Registry"
}

variable "workload_sa_name" {
  type        = string
  default     = "novatlantis-workload-sa"
  description = "ID da Service Account dos microsserviços Cloud Run"
}

variable "cicd_sa_name" {
  type        = string
  default     = "novatlantis-cicd-deployer"
  description = "ID da Service Account dedicada ao CI/CD e GitOps"
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_artifact_registry_repository" "gov_docker_repo" {
  project       = var.project_id
  location      = var.region
  repository_id = var.ar_repo_name
  format        = "DOCKER"
  description   = "Repositório Oficial de Imagens Container Imutáveis (dev e prod) da República Digital de Novatlantis"

  cleanup_policy_dry_run = false
  cleanup_policies {
    id     = "keep-minimum-10-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }
}

resource "google_secret_manager_secret" "jwt_authority" {
  project   = var.project_id
  secret_id = "novatlantis-internal-jwt-authority"

  replication {
    auto {}
  }

  labels = {
    nation     = "novatlantis"
    managed_by = "terraform-gitops"
  }
}

resource "google_secret_manager_secret_version" "jwt_authority_v1" {
  secret      = google_secret_manager_secret.jwt_authority.id
  secret_data = "novatlantis-sovereign-jwt-authority-${var.project_id}-2026"
}

resource "google_service_account" "workload_sa" {
  project      = var.project_id
  account_id   = var.workload_sa_name
  display_name = "Novatlantis Sovereign Microservices Workload Identity"
}

locals {
  workload_roles = toset([
    "roles/secretmanager.secretAccessor",
    "roles/alloydb.client",
    "roles/datastore.user",
    "roles/spanner.databaseUser",
    "roles/aiplatform.user",
    "roles/run.invoker"
  ])
}

resource "google_project_iam_member" "workload_sa_bindings" {
  for_each = local.workload_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.workload_sa.email}"
}

# ------------------------------------------------------------------------------
# WORKLOAD IDENTITY FEDERATION (WIF) + SERVICE ACCOUNT DE CI/CD (BOOTSTRAPPED)
# ------------------------------------------------------------------------------
data "google_service_account" "cicd_deployer_sa" {
  project    = var.project_id
  account_id = var.cicd_sa_name
}

output "artifact_registry_uri" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.gov_docker_repo.repository_id}"
  description = "URI base do repositório de imagens Docker no Artifact Registry"
}

output "workload_sa_email" {
  value       = google_service_account.workload_sa.email
  description = "E-mail da Service Account de execução dos microsserviços"
}

output "cicd_sa_email" {
  value       = data.google_service_account.cicd_deployer_sa.email
  description = "E-mail da Service Account de CI/CD e GitOps"
}

output "wif_provider_name" {
  value       = "projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/github-latam-ps-ce-pool/providers/github-oidc-provider"
  description = "Resource name completo do provedor OIDC do Workload Identity Federation"
}

output "jwt_secret_id" {
  value       = google_secret_manager_secret.jwt_authority.secret_id
  description = "Nome do segredo JWT no Secret Manager"
  depends_on  = [google_secret_manager_secret_version.jwt_authority_v1]
}
