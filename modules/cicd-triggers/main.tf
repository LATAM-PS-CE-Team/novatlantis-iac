# ==============================================================================
# MÓDULO TERRAFORM: GATILHOS NATIVOS DO GOOGLE CLOUD BUILD POR AMBIENTE/PROJETO
# Organização: https://github.com/LATAM-PS-CE-Team
# Repositório: novatlantis-iac/modules/cicd-triggers
# Mapeamento 1:1 de Projeto GCP <-> Branch <-> Ambiente:
#   - Projeto 'novatlantis-dev' | Branch 'dev'  | Ambiente 'dev'  (merge livre sem aprovação)
#   - Projeto 'novatlantis-prd' | Branch 'main' | Ambiente 'prod' (exige aprovação de @pedrocalixto)
# ==============================================================================

variable "project_id" {
  type        = string
  description = "ID do projeto Google Cloud (novatlantis-dev ou novatlantis-prd)"
}

variable "region" {
  type        = string
  default     = "us-central1"
}

variable "environment" {
  type        = string
  description = "Ambiente gerenciado pelo projeto: 'dev' ou 'prod'"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "O ambiente deve ser estritamente 'dev' ou 'prod'."
  }
}

variable "target_branch" {
  type        = string
  description = "Branch associada ao projeto/ambiente ('dev' para novatlantis-dev, 'main' para novatlantis-prd)"
  validation {
    condition     = contains(["dev", "main"], var.target_branch)
    error_message = "A branch associada deve ser estritamente 'dev' ou 'main'."
  }
}

variable "github_owner" {
  type        = string
  default     = "LATAM-PS-CE-Team"
  description = "Organização proprietária dos 3 repositórios no GitHub"
}

variable "app_repo_name" {
  type        = string
  default     = "novatlantis-app"
}

variable "iac_repo_name" {
  type        = string
  default     = "novatlantis-iac"
}

variable "data_repo_name" {
  type        = string
  default     = "novatlantis-data-platform"
}

variable "cicd_sa_id" {
  type        = string
  description = "Resource ID completo da Service Account do Cloud Build (projects/.../serviceAccounts/...)"
}

# ------------------------------------------------------------------------------
# 1. TRIGGERS DO REPOSITÓRIO DE APLICAÇÃO (LATAM-PS-CE-Team/novatlantis-app)
# ------------------------------------------------------------------------------
resource "google_cloudbuild_trigger" "app_pr_validation" {
  name            = "novatlantis-app-pr-${var.environment}"
  project         = var.project_id
  location        = var.region
  description     = "[CI ${upper(var.environment)}] Valida build TypeScript, Dockerfile e testes unitários ADK em PRs para a branch '${var.target_branch}'"
  service_account = var.cicd_sa_id
  filename        = "cloudbuild/cloudbuild-pr.yaml"

  github {
    owner = var.github_owner
    name  = var.app_repo_name
    pull_request {
      branch          = "^${var.target_branch}$"
      comment_control = "COMMENTS_ENABLED_FOR_EXTERNAL_CONTRIBUTORS_ONLY"
    }
  }

  substitutions = {
    _BASE_BRANCH_NAME = var.target_branch
  }
}

resource "google_cloudbuild_trigger" "app_deploy" {
  name            = "novatlantis-app-deploy-${var.environment}"
  project         = var.project_id
  location        = var.region
  description     = "[CD ${upper(var.environment)}] Merge na branch '${var.target_branch}' -> Build ${var.environment}-$SHORT_SHA e deploy em novatlantis-${var.environment}-* no projeto ${var.project_id}"
  service_account = var.cicd_sa_id
  filename        = "cloudbuild/cloudbuild-deploy.yaml"

  github {
    owner = var.github_owner
    name  = var.app_repo_name
    push {
      branch = "^${var.target_branch}$"
    }
  }

  substitutions = {
    _ENV            = var.environment
    _REGION         = var.region
    _SERVICE_PREFIX = "novatlantis-${var.environment}"
  }
}

# ------------------------------------------------------------------------------
# 2. TRIGGERS DO REPOSITÓRIO DE INFRAESTRUTURA (LATAM-PS-CE-Team/novatlantis-iac)
# ------------------------------------------------------------------------------
resource "google_cloudbuild_trigger" "iac_pr_plan" {
  name            = "novatlantis-iac-pr-plan-${var.environment}"
  project         = var.project_id
  location        = var.region
  description     = "[GitOps CI ${upper(var.environment)}] Executa terraform fmt, validate e plan (environments/${var.environment}) em PRs para '${var.target_branch}'"
  service_account = var.cicd_sa_id
  filename        = "cloudbuild/cloudbuild-tf-plan.yaml"

  github {
    owner = var.github_owner
    name  = var.iac_repo_name
    pull_request {
      branch          = "^${var.target_branch}$"
      comment_control = "COMMENTS_ENABLED_FOR_EXTERNAL_CONTRIBUTORS_ONLY"
    }
  }

  substitutions = {
    _TF_ENV = var.environment
  }
}

resource "google_cloudbuild_trigger" "iac_apply" {
  name            = "novatlantis-iac-apply-${var.environment}"
  project         = var.project_id
  location        = var.region
  description     = "[GitOps CD ${upper(var.environment)}] Merge na branch '${var.target_branch}' -> Executa terraform apply em environments/${var.environment} no projeto ${var.project_id}"
  service_account = var.cicd_sa_id
  filename        = "cloudbuild/cloudbuild-tf-apply.yaml"

  github {
    owner = var.github_owner
    name  = var.iac_repo_name
    push {
      branch = "^${var.target_branch}$"
    }
  }

  substitutions = {
    _TF_ENV = var.environment
  }
}

# ------------------------------------------------------------------------------
# 3. TRIGGERS DO REPOSITÓRIO DE DADOS (LATAM-PS-CE-Team/novatlantis-data-platform)
# ------------------------------------------------------------------------------
resource "google_cloudbuild_trigger" "data_pr_validation" {
  name            = "novatlantis-data-pr-${var.environment}"
  project         = var.project_id
  location        = var.region
  description     = "[Data CI ${upper(var.environment)}] Valida sintaxe Python, schemas JSON e SQL DDL em PRs para '${var.target_branch}'"
  service_account = var.cicd_sa_id
  filename        = "cloudbuild/cloudbuild-pr.yaml"

  github {
    owner = var.github_owner
    name  = var.data_repo_name
    pull_request {
      branch = "^${var.target_branch}$"
    }
  }
}

resource "google_cloudbuild_trigger" "data_deploy" {
  name            = "novatlantis-data-deploy-${var.environment}"
  project         = var.project_id
  location        = var.region
  description     = "[Data CD ${upper(var.environment)}] Merge na branch '${var.target_branch}' -> Sincroniza schemas e Views Medallion em ${var.environment} (${var.project_id})"
  service_account = var.cicd_sa_id
  filename        = "cloudbuild/cloudbuild-deploy.yaml"

  github {
    owner = var.github_owner
    name  = var.data_repo_name
    push {
      branch = "^${var.target_branch}$"
    }
  }

  substitutions = {
    _ENV = var.environment
  }
}
