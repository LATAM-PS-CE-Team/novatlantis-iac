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

variable "domain" {
  type    = string
  default = "dev.gov.novatlantis.cloud"
}

variable "github_owner" {
  type    = string
  default = "LATAM-PS-CE-Team"
}

variable "enable_alloydb_cluster" {
  type        = bool
  default     = false
  description = "Habilita provisionamento de cluster AlloyDB dedicado (os microsserviços possuem engine híbrido SQLite + AlloyDB)"
}

variable "enable_cloudbuild_github_app_triggers" {
  type        = bool
  default     = false
  description = "Habilita gatilhos nativos Cloud Build GitHub App (requer vínculo OAuth prévio no console; GitHub Actions via WIF já dispara o Cloud Build)"
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
  count      = var.enable_alloydb_cluster ? 1 : 0
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

module "edge_lb_armor_dev" {
  source        = "../../modules/edge-lb-armor"
  project_id    = var.project_id
  region        = var.region
  environment   = "dev"
  domain        = var.domain
  service_names = module.cloud_run_dev.service_names
}

module "cicd_triggers_dev" {
  count         = var.enable_cloudbuild_github_app_triggers ? 1 : 0
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
  description = "URLs do Ambiente DEV dos 9 microsserviços Cloud Run no projeto novatlantis-dev"
}

output "dev_lb_ip_address" {
  value       = module.edge_lb_armor_dev.lb_ip_address
  description = "IP Global Anycast do Load Balancer DEV (apontar dev.gov.novatlantis.cloud e *.dev.gov.novatlantis.cloud no GoDaddy)"
}

output "dev_custom_domain_urls" {
  value       = module.edge_lb_armor_dev.custom_domain_urls
  description = "URLs customizadas do Ambiente DEV (dev.gov.novatlantis.cloud)"
}
