# ==============================================================================
# AMBIENTE DEV — REPÚBLICA DIGITAL DE NOVATLANTIS
# Organização GitHub: https://github.com/LATAM-PS-CE-Team
# Branch Alvo: dev (Merge livre sem necessidade de aprovação humana)
# Projeto GCP Dedicado: novatlantis-dev
# Backend Remoto: gs://novatlantis-dev-tfstate/iac/dev (com State Locking)
# ==============================================================================

terraform {
  required_version = ">= 1.6.0"

  backend "gcs" {
    bucket = "novatlantis-dev-tfstate"
    prefix = "iac/dev"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.30"
    }
  }
}

variable "project_id" {
  type    = string
  default = "novatlantis-dev"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "github_owner" {
  type    = string
  default = "LATAM-PS-CE-Team"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "networking" {
  source     = "../../modules/networking"
  project_id = var.project_id
  region     = var.region
}

module "database_alloydb" {
  source     = "../../modules/database-alloydb"
  project_id = var.project_id
  region     = var.region
  vpc_id     = module.networking.vpc_id
  depends_on = [module.networking]
}

module "security_iam_secrets" {
  source       = "../../modules/security-iam-secrets"
  project_id   = var.project_id
  region       = var.region
  github_owner = var.github_owner
}

module "cloud_run_dev" {
  source            = "../../modules/cloud-run-services"
  project_id        = var.project_id
  region            = var.region
  environment       = "dev"
  service_prefix    = "novatlantis-dev"
  workload_sa_email = module.security_iam_secrets.workload_sa_email
  jwt_secret_id     = module.security_iam_secrets.jwt_secret_id
  ar_repo_name      = "novatlantis-gov-repo"
  depends_on        = [module.security_iam_secrets]
}

module "cicd_triggers_dev" {
  source        = "../../modules/cicd-triggers"
  project_id    = var.project_id
  region        = var.region
  environment   = "dev"
  target_branch = "dev"
  github_owner  = var.github_owner
  cicd_sa_id    = "projects/${var.project_id}/serviceAccounts/novatlantis-cicd-deployer@${var.project_id}.iam.gserviceaccount.com"
}

output "dev_service_urls" {
  value       = module.cloud_run_dev.service_urls
  description = "URLs do Ambiente DEV dos 8 microsserviços Cloud Run no projeto novatlantis-dev"
}
