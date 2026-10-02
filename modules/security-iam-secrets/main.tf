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
# WORKLOAD IDENTITY FEDERATION (WIF) + SERVICE ACCOUNT DE CI/CD
# ------------------------------------------------------------------------------
resource "google_service_account" "cicd_deployer_sa" {
  project      = var.project_id
  account_id   = var.cicd_sa_name
  display_name = "Novatlantis CI/CD & Terraform GitOps Deployer (WIF + Cloud Build)"
}

resource "google_iam_workload_identity_pool" "github_pool" {
  project                   = var.project_id
  workload_identity_pool_id = "github-latam-ps-ce-pool"
  display_name              = "LATAM-PS-CE-Team GitHub Pool"
  description               = "Workload Identity Pool para autenticar pipelines da org ${var.github_owner} sem chaves JSON"
}

resource "google_iam_workload_identity_pool_provider" "github_oidc" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc-provider"
  display_name                       = "GitHub OIDC Provider (${var.github_owner})"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  attribute_condition = "assertion.repository_owner == '${var.github_owner}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "wif_github_binding" {
  service_account_id = google_service_account.cicd_deployer_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository_owner/${var.github_owner}"
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
  value       = google_service_account.cicd_deployer_sa.email
  description = "E-mail da Service Account de CI/CD e GitOps"
}

output "wif_provider_name" {
  value       = google_iam_workload_identity_pool_provider.github_oidc.name
  description = "Resource name completo do provedor OIDC do Workload Identity Federation"
}

output "jwt_secret_id" {
  value       = google_secret_manager_secret.jwt_authority.secret_id
  description = "Nome do segredo JWT no Secret Manager"
}
