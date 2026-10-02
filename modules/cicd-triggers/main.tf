# ==============================================================================
# MÓDULO TERRAFORM: GATILHOS NATIVOS DO GOOGLE CLOUD BUILD (AMBIENTES 'dev' E 'prod')
# Organização: https://github.com/LATAM-PS-CE-Team
# Repositório: novatlantis-iac/modules/cicd-triggers
# Mapeamento de Branches:
#   - Branch 'dev'  -> Dispara deploy/apply automático no Ambiente 'dev' (merge livre sem aprovação)
#   - Branch 'main' -> Dispara deploy/apply automático no Ambiente 'prod' (após aprovação de @pedrocalixto)
# ==============================================================================

variable "project_id" {
  type        = string
  description = "ID do projeto Google Cloud"
}

variable "region" {
  type        = string
  default     = "us-central1"
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
  name            = "novatlantis-app-pr-check"
  project         = var.project_id
  location        = var.region
  description     = "[CI] Valida build TypeScript, Dockerfile e testes unitários ADK em Pull Requests (branches dev e main)"
  service_account = var.cicd_sa_id
  filename        = "cloudbuild/cloudbuild-pr.yaml"

  github {
    owner = var.github_owner
    name  = var.app_repo_name
    pull_request {
      branch          = "^(dev|main)$"
      comment_control = "COMMENTS_ENABLED_FOR_EXTERNAL_CONTRIBUTORS_ONLY"
    }
  }

  substitutions = {
    _BASE_BRANCH_NAME = "dev"
  }
}

resource "google_cloudbuild_trigger" "app_deploy_dev" {
  name            = "novatlantis-app-deploy-dev"
  project         = var.project_id
  location        = var.region
  description     = "[CD Ambiente DEV] Merge livre na branch 'dev' -> Build dev-$SHORT_SHA e deploy em novatlantis-dev-*"
  service_account = var.cicd_sa_id
  filename        = "cloudbuild/cloudbuild-deploy.yaml"

  github {
    owner = var.github_owner
    name  = var.app_repo_name
    push {
      branch = "^dev$"
    }
  }

  substitutions = {
    _ENV            = "dev"
    _REGION         = var.region
    _SERVICE_PREFIX = "novatlantis-dev"
  }
}

resource "google_cloudbuild_trigger" "app_deploy_prod" {
  name            = "novatlantis-app-deploy-prod"
  project         = var.project_id
  location        = var.region
  description     = "[CD Ambiente PROD] Merge aprovado por @pedrocalixto na branch 'main' -> Build prod-$SHORT_SHA e deploy em novatlantis-prod-*"
  service_account = var.cicd_sa_id
  filename        = "cloudbuild/cloudbuild-deploy.yaml"

  github {
    owner = var.github_owner
    name  = var.app_repo_name
    push {
      branch = "^main$"
    }
  }

  substitutions = {
    _ENV            = "prod"
    _REGION         = var.region
    _SERVICE_PREFIX = "novatlantis-prod"
  }
}

# ------------------------------------------------------------------------------
# 2. TRIGGERS DO REPOSITÓRIO DE INFRAESTRUTURA (LATAM-PS-CE-Team/novatlantis-iac)
# ------------------------------------------------------------------------------
resource "google_cloudbuild_trigger" "iac_pr_plan" {
  name            = "novatlantis-iac-pr-plan"
  project         = var.project_id
  location        = var.region
  description     = "[GitOps CI] Executa terraform fmt, validate e plan (environments/dev e environments/prod) em Pull Requests"
  service_account = var.cicd_sa_id
  filename        = "cloudbuild/cloudbuild-tf-plan.yaml"

  github {
    owner = var.github_owner
    name  = var.iac_repo_name
    pull_request {
      branch          = "^(dev|main)$"
      comment_control = "COMMENTS_ENABLED_FOR_EXTERNAL_CONTRIBUTORS_ONLY"
    }
  }
}

resource "google_cloudbuild_trigger" "iac_apply_dev" {
  name            = "novatlantis-iac-apply-dev"
  project         = var.project_id
  location        = var.region
  description     = "[GitOps CD DEV] Merge livre na branch 'dev' -> Executa terraform apply em environments/dev"
  service_account = var.cicd_sa_id
  filename        = "cloudbuild/cloudbuild-tf-apply.yaml"

  github {
    owner = var.github_owner
    name  = var.iac_repo_name
    push {
      branch = "^dev$"
    }
  }

  substitutions = {
    _TF_ENV = "dev"
  }
}

resource "google_cloudbuild_trigger" "iac_apply_prod" {
  name            = "novatlantis-iac-apply-prod"
  project         = var.project_id
  location        = var.region
  description     = "[GitOps CD PROD] Merge aprovado por @pedrocalixto na branch 'main' -> Executa terraform apply em environments/prod"
  service_account = var.cicd_sa_id
  filename        = "cloudbuild/cloudbuild-tf-apply.yaml"

  github {
    owner = var.github_owner
    name  = var.iac_repo_name
    push {
      branch = "^main$"
    }
  }

  substitutions = {
    _TF_ENV = "prod"
  }
}

# ------------------------------------------------------------------------------
# 3. TRIGGERS DO REPOSITÓRIO DE DADOS (LATAM-PS-CE-Team/novatlantis-data-platform)
# ------------------------------------------------------------------------------
resource "google_cloudbuild_trigger" "data_pr_validation" {
  name            = "novatlantis-data-pr-check"
  project         = var.project_id
  location        = var.region
  description     = "[Data CI] Valida sintaxe Python, schemas JSON e SQL DDL em Pull Requests (branches dev e main)"
  service_account = var.cicd_sa_id
  filename        = "cloudbuild/cloudbuild-pr.yaml"

  github {
    owner = var.github_owner
    name  = var.data_repo_name
    pull_request {
      branch = "^(dev|main)$"
    }
  }
}

resource "google_cloudbuild_trigger" "data_deploy_dev" {
  name            = "novatlantis-data-deploy-dev"
  project         = var.project_id
  location        = var.region
  description     = "[Data CD DEV] Merge livre na branch 'dev' -> Sincroniza schemas e Views Medallion em dev"
  service_account = var.cicd_sa_id
  filename        = "cloudbuild/cloudbuild-deploy.yaml"

  github {
    owner = var.github_owner
    name  = var.data_repo_name
    push {
      branch = "^dev$"
    }
  }

  substitutions = {
    _ENV = "dev"
  }
}

resource "google_cloudbuild_trigger" "data_deploy_prod" {
  name            = "novatlantis-data-deploy-prod"
  project         = var.project_id
  location        = var.region
  description     = "[Data CD PROD] Merge aprovado por @pedrocalixto na branch 'main' -> Sincroniza schemas e Views Medallion em prod"
  service_account = var.cicd_sa_id
  filename        = "cloudbuild/cloudbuild-deploy.yaml"

  github {
    owner = var.github_owner
    name  = var.data_repo_name
    push {
      branch = "^main$"
    }
  }

  substitutions = {
    _ENV = "prod"
  }
}
