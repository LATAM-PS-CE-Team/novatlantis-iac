# ==============================================================================
# AMBIENTE DEV — REPÚBLICA DIGITAL DE NOVATLANTIS
# Organização: https://github.com/LATAM-PS-CE-Team
# Branch Alvo: main (Merge livre sem necessidade de aprovação humana)
# Backend Remoto: gs://novatlantis-tfstate/iac/dev (com State Locking)
# ==============================================================================

terraform {
  required_version = ">= 1.6.0"

  backend "gcs" {
    bucket = "novatlantis-tfstate"
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
  default = "novatlantis"
}

variable "region" {
  type    = string
  default = "us-central1"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# No ambiente 'dev', reutilizamos o Artifact Registry e a Service Account de Workload
# e provisionamos os 8 serviços Cloud Run com prefixo isolado 'novatlantis-dev-*'.
module "cloud_run_dev" {
  source            = "../../modules/cloud-run-services"
  project_id        = var.project_id
  region            = var.region
  environment       = "dev"
  service_prefix    = "novatlantis-dev"
  workload_sa_email = "novatlantis-workload-sa@${var.project_id}.iam.gserviceaccount.com"
  jwt_secret_id     = "novatlantis-internal-jwt-authority"
  ar_repo_name      = "novatlantis-gov-repo"
}

output "dev_service_urls" {
  value       = module.cloud_run_dev.service_urls
  description = "URLs do Ambiente DEV dos 8 microsserviços Cloud Run (novatlantis-dev-*)"
}
