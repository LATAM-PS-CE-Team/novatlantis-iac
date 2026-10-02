# ==============================================================================
# AMBIENTE PROD — REPÚBLICA DIGITAL DE NOVATLANTIS
# Organização GitHub: https://github.com/LATAM-PS-CE-Team
# Branch Alvo: main (Exige aprovação explícita de @pedrocalixto via CODEOWNERS)
# Projeto GCP Dedicado: novatlantis-prd
# Backend Remoto: gs://novatlantis-prd-tfstate/iac/prod (com State Locking)
# ==============================================================================

terraform {
  required_version = ">= 1.6.0"

  backend "gcs" {
    bucket = "novatlantis-prd-tfstate"
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
  default = "novatlantis-prd"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "domain" {
  type    = string
  default = "gov.novatlantis.cloud"
}

variable "github_owner" {
  type    = string
  default = "LATAM-PS-CE-Team"
}

variable "enable_alloydb_cluster" {
  type        = bool
  default     = false
  description = "Habilita provisionamento de cluster AlloyDB dedicado"
}

variable "enable_cloudbuild_github_app_triggers" {
  type        = bool
  default     = false
  description = "Habilita gatilhos nativos Cloud Build GitHub App"
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
  environment   = "prod"
  domain        = var.domain
  service_names = module.cloud_run_prod.service_names
}

module "cicd_triggers_prod" {
  count         = var.enable_cloudbuild_github_app_triggers ? 1 : 0
  source        = "../../modules/cicd-triggers"
  project_id    = var.project_id
  region        = var.region
  environment   = "prod"
  target_branch = "main"
  github_owner  = var.github_owner
  cicd_sa_id    = "projects/${var.project_id}/serviceAccounts/novatlantis-cicd-deployer@${var.project_id}.iam.gserviceaccount.com"
}

output "prod_service_urls" {
  value       = module.cloud_run_prod.service_urls
  description = "URLs oficiais do Ambiente PROD dos 9 microsserviços Cloud Run no projeto novatlantis-prd"
}

output "prod_lb_ip_address" {
  value       = module.edge_lb_armor.lb_ip_address
  description = "IP Global Anycast do Load Balancer PROD (apontar gov.novatlantis.cloud e *.gov.novatlantis.cloud no GoDaddy)"
}

output "prod_custom_domain_urls" {
  value       = module.edge_lb_armor.custom_domain_urls
  description = "URLs customizadas do Ambiente PROD (gov.novatlantis.cloud)"
}

output "alloydb_private_ip" {
  value       = var.enable_alloydb_cluster ? module.database_alloydb[0].primary_instance_ip : "HYBRID_SQLITE_ACTIVE"
  description = "IP Privado (PSA) da instância primária AlloyDB"
}
