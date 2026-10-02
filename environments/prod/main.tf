# ==============================================================================
# AMBIENTE PROD — REPÚBLICA DIGITAL DE NOVATLANTIS
# Organização: https://github.com/LATAM-PS-CE-Team
# Branch Alvo: prod (Exige aprovação explícita de @pedrocalixto via CODEOWNERS)
# Backend Remoto: gs://novatlantis-tfstate/iac/prod (com State Locking)
# ==============================================================================

terraform {
  required_version = ">= 1.6.0"

  backend "gcs" {
    bucket = "novatlantis-tfstate"
    prefix = "iac/prod"
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
  default = "novatlantis"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "domain" {
  type    = string
  default = "novatlantis.gov.cloud"
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
  source     = "../../modules/security-iam-secrets"
  project_id = var.project_id
  region     = var.region
}

module "cloud_run_prod" {
  source            = "../../modules/cloud-run-services"
  project_id        = var.project_id
  region            = var.region
  environment       = "prod"
  service_prefix    = "novatlantis-prod"
  workload_sa_email = module.security_iam_secrets.workload_sa_email
  jwt_secret_id     = module.security_iam_secrets.jwt_secret_id
  depends_on        = [module.security_iam_secrets]
}

module "edge_lb_armor" {
  source        = "../../modules/edge-lb-armor"
  project_id    = var.project_id
  region        = var.region
  domain        = var.domain
  service_names = module.cloud_run_prod.service_names
}

module "cicd_triggers" {
  source       = "../../modules/cicd-triggers"
  project_id   = var.project_id
  region       = var.region
  github_owner = var.github_owner
  cicd_sa_id   = "projects/${var.project_id}/serviceAccounts/novatlantis-cicd-deployer@${var.project_id}.iam.gserviceaccount.com"
}

output "prod_service_urls" {
  value       = module.cloud_run_prod.service_urls
  description = "URLs oficiais do Ambiente PROD dos 8 microsserviços Cloud Run (novatlantis-prod-*)"
}

output "alloydb_private_ip" {
  value       = module.database_alloydb.primary_instance_ip
  description = "IP Privado (PSA) da instância primária AlloyDB"
}
